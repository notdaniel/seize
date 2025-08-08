require "http/client"
require "option_parser"
require "file"
require "colorize"

module Seize
  VERSION = "0.1.0"

  class ParallelDownloader
    BUFFER_SIZE = 8192

    def initialize(@url : String, @output_file : String? = nil, @segments_count : Int32 = 10)
      @segments = [] of Segment
      @total_size = 0_i64
    end

    class Segment
      property start_byte : Int64
      property end_byte : Int64
      property data : IO::Memory
      property downloaded : Bool

      def initialize(@start_byte : Int64, @end_byte : Int64)
        @data = IO::Memory.new
        @downloaded = false
      end

      def size
        end_byte - start_byte + 1
      end
    end

    def download : Bool
      puts "Checking URL: #{@url}".colorize(:cyan)

      unless get_file_info
        puts "Failed to get file information, falling back to single request".colorize(:red)
        return download_single_request
      end

      puts "File size: #{format_bytes(@total_size)}".colorize(:green)
      puts "Starting parallel download with #{@segments_count} segments...".colorize(:cyan)

      create_segments
      download_parallel
      reconstruct_file
    end

    private def get_file_info : Bool
      uri = URI.parse(@url)

      HTTP::Client.new(uri) do |client|
        response = client.head(uri.path.presence || "/")

        if response.status.success?
          if content_length = response.headers["Content-Length"]?
            @total_size = content_length.to_i64

            accept_ranges = response.headers["Accept-Ranges"]?
            if accept_ranges != "bytes"
              puts "Server doesn't support range requests".colorize(:yellow)
              return false
            end

            return true
          end
        end
      end

      false
    rescue ex
      puts "Error getting file info: #{ex.message}".colorize(:red)
      false
    end

    private def create_segments
      segment_size = @total_size // @segments_count
      remainder = @total_size % @segments_count

      current_pos = 0_i64

      @segments_count.times do |i|
        start_byte = current_pos
        end_byte = current_pos + segment_size - 1

        if i == @segments_count - 1
          end_byte += remainder
        end

        @segments << Segment.new(start_byte, end_byte)
        current_pos = end_byte + 1
      end
    end

    private def download_parallel
      # completion channel, i always fuck this up      # Create completion channel for fiber coordination
      completion_channel = Channel(Bool).new

      # parallelize
      @segments.each_with_index do |segment, index|
        spawn do
          begin
            download_segment(segment, index)
            completion_channel.send(true)
          rescue ex
            puts "\n Segment #{index} failed: #{ex.message}".colorize(:red)
            completion_channel.send(false)
          end
        end
      end

      success_count = 0
      @segments.size.times do |i|
        if completion_channel.receive
          success_count += 1
        end

        progress = (success_count.to_f / @segments.size * 100).round(1)
        downloaded_size = @segments.select(&.downloaded).sum(&.data.size)
        print "\rProgress: #{progress}% (#{format_bytes(downloaded_size)}/#{format_bytes(@total_size)})"
      end

      if success_count != @segments.size
        raise "Failed to download all segments (#{success_count}/#{@segments.size} succeeded)"
      end

      puts "\nAll segments downloaded successfully!".colorize(:green)
    end

    private def download_segment(segment : Segment, index : Int32)
      uri = URI.parse(@url)

      HTTP::Client.new(uri) do |client|
        headers = HTTP::Headers.new
        headers["Range"] = "bytes=#{segment.start_byte}-#{segment.end_byte}"

        response = client.get(uri.path.presence || "/", headers: headers)

        if response.status.partial_content? || response.status.success?
          body = response.body
          if body && !body.empty?
            segment.data.write(body.to_slice)
            segment.downloaded = true
          else
            raise "Response body is empty"
          end
        else
          raise "Failed to download segment #{index}: #{response.status} #{response.status_message}"
        end
      end
    rescue ex
      segment.downloaded = false # Explicitly mark as failed
      puts "\n Error downloading segment #{index}: #{ex.message}".colorize(:red)
      raise ex
    end

    private def reconstruct_file : Bool
      output_filename = @output_file || extract_filename

      puts "Reconstructing file: #{output_filename}".colorize(:cyan)

      File.open(output_filename, "w") do |file|
        @segments.each_with_index do |segment, index|
          unless segment.downloaded
            puts "Segment #{index} was not downloaded successfully".colorize(:red)
            return false
          end

          segment.data.rewind
          IO.copy(segment.data, file)
        end
      end

      puts "File reconstructed successfully: #{output_filename}".colorize(:green)
      puts "Final size: #{format_bytes(File.size(output_filename))}".colorize(:green)
      true
    end

    private def download_single_request : Bool
      puts "Downloading with single request...".colorize(:yellow)

      uri = URI.parse(@url)
      output_filename = @output_file || extract_filename

      HTTP::Client.new(uri) do |client|
        response = client.get(uri.path.presence || "/")

        if response.status.success?
          File.open(output_filename, "w") do |file|
            IO.copy(response.body_io, file)
          end

          puts "Single request download completed: #{output_filename}".colorize(:green)
          return true
        else
          puts "Download failed: #{response.status}".colorize(:red)
          return false
        end
      end
    rescue ex
      puts "Download error: #{ex.message}".colorize(:red)
      false
    end

    private def extract_filename : String
      uri = URI.parse(@url)
      filename = File.basename(uri.path.presence || "download")
      filename.empty? ? "download" : filename
    end

    private def format_bytes(bytes : Int64) : String
      units = ["B", "KB", "MB", "GB", "TB"]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(2)} #{units[unit_index]}"
    end
  end

  def self.run
    url = ""
    output_file = nil
    segments_count = 10

    OptionParser.parse do |parser|
      parser.banner = "Usage: seize [options] URL"
      parser.on("-o FILE", "--output=FILE", "Output filename") { |file| output_file = file }
      parser.on("-s COUNT", "--segments=COUNT", "Number of parallel segments (default: 10)") do |count|
        segments_count = count.to_i
        if segments_count < 1 || segments_count > 50
          puts "Error: Segments count must be between 1 and 50".colorize(:red)
          exit(1)
        end
      end
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit
      end
      parser.on("-v", "--version", "Show version") do
        puts "seize version #{VERSION}"
        exit
      end
      parser.unknown_args do |args|
        if args.size == 1
          url = args[0]
        else
          puts parser
          exit(1)
        end
      end
    end

    if url.empty?
      puts "Error: URL is required".colorize(:red)
      puts "Usage: seize [options] URL"
      exit(1)
    end

    puts "Seize v#{VERSION} - Parallel File Downloader".colorize(:magenta).bold
    puts "="*50

    downloader = ParallelDownloader.new(url, output_file, segments_count)
    success = downloader.download

    exit(success ? 0 : 1)
  end
end

Seize.run
