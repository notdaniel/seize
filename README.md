# Seize

A fast, parallel file downloader written in Crystal that accelerates downloads by splitting files into multiple segments and downloading them concurrently using fibers.

## Features

- **Parallel Downloads**: Downloads files using 10 concurrent segments with HTTP range requests
- **Smart Fallback**: Automatically falls back to single-request download if the server doesn't support range requests
- **Progress Tracking**: Real-time progress display with download speeds and file sizes
- **Cross-platform**: Works on macOS, Linux, and Windows
- **Beautiful Output**: Colorized terminal output with emoji indicators
- **Resume Support**: Built-in handling for partial content and range requests

## How It Works

1. **HEAD Request**: First checks the file size and server support for range requests
2. **Segment Calculation**: Divides the file into N equal segments (default 10, configurable 1-50)
3. **Parallel Download**: Uses Crystal fibers to download each segment concurrently with HTTP range headers
4. **File Reconstruction**: Merges all segments back into the complete file in the correct order
5. **Fallback**: If range requests aren't supported, falls back to a standard single request

## Installation

### From Source

```bash
git clone <repository-url>
cd seize
crystal build src/seize.cr --release
sudo mv seize /usr/local/bin/
```

### Building

```bash
crystal build src/seize.cr
```

## Usage

### Basic Usage

```bash
# Download a file (default 10 segments)
./seize https://example.com/largefile.zip

# Download with custom output filename
./seize -o myfile.zip https://example.com/largefile.zip
./seize --output=myfile.zip https://example.com/largefile.zip

# Download with custom number of segments
./seize -s 5 https://example.com/largefile.zip
./seize --segments=20 https://example.com/largefile.zip
```

### Command Line Options

```
Usage: seize [options] URL

Options:
    -o FILE, --output=FILE           Output filename
    -s COUNT, --segments=COUNT       Number of parallel segments (default: 10)
    -h, --help                       Show help
    -v, --version                    Show version
```

### Examples

```bash
# Download a Linux ISO (default 10 segments)
./seize https://releases.ubuntu.com/20.04/ubuntu-20.04.6-desktop-amd64.iso

# Download with custom filename and 5 segments
./seize -o ubuntu.iso -s 5 https://releases.ubuntu.com/20.04/ubuntu-20.04.6-desktop-amd64.iso

# Download with 20 segments for very large files
./seize --segments=20 https://example.com/very-large-file.zip

# Single segment download (no parallelization)
./seize -s 1 https://example.com/file.zip

# The tool will automatically:
# - Check if the server supports range requests
# - Split the download into the specified number of parallel segments
# - Show real-time progress
# - Reconstruct the complete file
```

## Output Example

```
🎯 Seize v0.1.0 - Parallel File Downloader
==================================================
🔍 Checking URL: https://example.com/largefile.zip
📊 File size: 150.25 MB
🚀 Starting parallel download with 10 segments...
📥 Progress: 67.3% (101.14 MB/150.25 MB)
✅ All segments downloaded successfully!
🔧 Reconstructing file: largefile.zip
🎉 File reconstructed successfully: largefile.zip
📁 Final size: 150.25 MB
```

## Technical Details

- **Concurrency**: Uses Crystal's lightweight fibers for efficient concurrent downloads
- **Memory Efficient**: Streams data directly to segments without loading entire file into memory
- **HTTP Range Requests**: Uses `Range: bytes=start-end` headers for segment downloads
- **Error Handling**: Comprehensive error handling with graceful fallbacks
- **Progress Display**: Thread-safe progress updates using channels and mutexes

## Development

```bash
# Run development version
crystal run src/seize.cr -- https://example.com/file.zip

# Run tests
crystal spec

# Build release version
crystal build src/seize.cr --release
```

## Contributing

1. Fork it (<https://github.com/your-github-user/seize/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributors

- [your-name-here](https://github.com/your-github-user) - creator and maintainer
