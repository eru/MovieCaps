# MovieCaps

This shell script creates a sheet with screen captures from a movie.

## Requirements

- Linux standard GNU utils (should also work under \*BSD and Solaris)
- getopt (normally part of the GNU utils)
- awk/gawk/mawk
- Mplayer
- ImageMagick
- FFmpeg

## Files

- make\_caps.sh

## Installation

1. Download make\_caps.sh and put it somewhere into your $PATH (e.g. /usr/local/bin).
2. Make the file executable: `chmod a+x make_caps.sh`.

## Usage

Type `make_caps.sh --help` to get a short description of the program.

## Work cycle

`make_caps.sh` determines which frames are to be captured. For every frame, it

1. Captures the frame with mplayer, optionaly scaling it.
2. If requested, the frame is cropped.
3. A timestamp is added to the picture.
