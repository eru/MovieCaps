#!/usr/bin/env bash

# Default values
DEFAULT_INTERVAL=30
DEFAULT_FS=24
DEFAULT_PREFIX="cap_"
VERSION="0.7"

# Set default values
OFFSET=0
INTERVAL=$DEFAULT_INTERVAL
FONTSIZE=$DEFAULT_FS
SCALE_FACTOR=1
PREFIX=$DEFAULT_PREFIX
NUM_COLS=4
unset CROP_SPEC DO_PAUSE
EXEC_DIR=$(/bin/pwd)
CAPTURE_DIR=${EXEC_DIR}
DEBUG=0

debug () {
cat <<EOF
OFFSET       = ${OFFSET}
LENGTH       = ${LENGTH}
INTERVAL     = ${INTERVAL}
NUM_CAPS     = ${NUM_CAPS}
STEPS        = ${STEPS}
FONTSIZE     = ${FONTSIZE}
SCALE_FACTOR = ${SCALE_FACTOR}
PREFIX       = ${PREFIX}
EOF
}

print_help () {
cat <<EOF

Usage: $(basename "$0") [OPTIONS] <filename of the movie>
 -o, --offset <start in seconds>           Start capturing here (default: 0).
 -e, --end <end in seconds>                End capturing here (default: length of the movie). Specifying a negative ends capturing an movielength-value.
 -i, --interval <time between screencaps>  Interval between screencaps (default: ${DEFAULT_INTERVAL}).
 -n, --number <number of screencaps>       Specify how many screencaps should be taken. This overwrites -i.

 -s, --scale <scale factor>                Scale the screencaps by this factor (default: no scaling).
 -w, --width <width in pixels>             Scale the screencaps to fit the width. This overwrites -s.

 -c, --crop <crop-spec>                    Crop the images using Imagemagick. See ImageMagick(1) details.
 -a, --autocrop                            Trim the picture's edges via an simple heuristic.

 -p, --prefix <prefix>                     Prefix of the screencaps (default: ${DEFAULT_PREFIX}).

 -x, --no-timestamps                       Don't write timestamps into the screencaps.
 -f, --fontsize <fontsite in pixels>       Default is ${DEFAULT_FS}.

 -l, --columns <number of columns>         Number of columns the final picture sheets should have (default: $NUM_COLS).
     --pause                               Wait before composing the final picture. You may modify or delete some of the
                                           screencaps before they are composed into the final image.
     --dont-delete-caps                    Do not delete the screen captures afterwards.

 -d, --capture-dir                         Screen captures output directory.

 -h, --help                                Print this message and exit.
 -V, --version                             Print the version and exit.

     --debug                               Debug mode.

EOF
}

# See http://unix.stackexchange.com/questions/101080/realpath-command-not-found
realpath ()
{
  f=$@;
  if [ -d "$f" ]; then
    base="";
    dir="$f";
  else
    base="/$(basename "$f")";
    dir=$(dirname "$f");
  fi;
  dir=$(cd "$dir" && /bin/pwd);
  echo "$dir$base"
}

# Check if the required software is available
for i in getopt mplayer magick ffmpeg printf awk bc; do
  if ! command -v "${i}" > /dev/null 2>&1; then
    echo "Error: Unable to find ${i}."
    exit 4
  fi
done

# Parse the arguments
TEMP_OPT=$(getopt -a \
  -o e:,o:,i:,n:,f:,s:,w:,p:,h,V,c:,x,a,l:,d: \
  --long end:,offset:,interval:,number:,fontsize:,scale:,width:,prefix:,help,version,crop:,autocrop,no-timestamps,columns:,pause,dont-delete-caps,capture-dir:,cature-dir:,debug \
  -- "$@")

if [ $? != 0 ]; then
  echo "Error executing getopt. Terminating..." >&2
  exit 1
fi

eval set -- "$TEMP_OPT"

while true ; do
  case "$1" in
    -o|--offset|-offset) OFFSET=$2; shift 2;;
    -e|--end|-end) LENGTH=$2; shift 2;;
    -i|--interval|-interval) INTERVAL=$2; shift 2;;
    -n|--number|-number) NUM_CAPS=$2; shift 2;;
    -f|--fontsize|-fontsize) FONTSIZE=$2; shift 2;;
    -s|--scale|-scale) SCALE_FACTOR=$2; shift 2;;
    -w|--width|-width) WIDTH=$2; shift 2;;
    -p|--prefix|-prefix) PREFIX=$2; shift 2;;
    -c|--crop|-crop) CROP_SPEC=$2; shift 2;;
    -a|--autocrop|-autocrop) AUTOCROP=1; shift 1;;
    -x|--no-timestamps|-no-timestamps) NO_TIMESTAMPS=1; shift 1;;
    -l|--columns|-column) NUM_COLS=$2; shift 2;;
       --pause|-pause) DO_PAUSE=1; shift 1;;
       --dont-delete-caps|-dont-delete-caps) DO_NOT_DELETE_CAPS=1; shift 1;;
    -d|--capture-dir|--cature-dir|-capture-dir|-cature-dir) CAPTURE_DIR=$2; shift 2;;
    -h|--help|-help) print_help; exit 0;;
    -V|--version|-version) echo "$(basename "${0}"), Version ${VERSION}"; exit 0;;
    --debug) DEBUG=1; shift 1;;
    --) shift ; break ;;
    *) echo "Unknown parameter $1." ; exit 1 ;;
  esac
done

# Debug
if [ "${DEBUG}" -eq 1 ]; then
  debug
  set -x
fi

# Handle the filename of the movie
MOVIEFILENAME="$(realpath "${1}")"
echo "$MOVIEFILENAME"
if [ ! -f "${MOVIEFILENAME}" ]; then
  echo "Error: Please specify a filename for the movie."
  print_help
  exit 2
fi

if [ ! -r "${MOVIEFILENAME}" ]; then
  echo "Error: Unable to read file \"$MOVIEFILENAME\"."
  exit 3
fi

if [ ! -d "${CAPTURE_DIR}" ]; then
  echo "Error: Capture directory does not exist."
  exit 6
fi

calculate_movie_length () {
  eval $(mplayer -vo null -ao null -frames 0 -identify "${MOVIEFILENAME}" 2> /dev/null | grep ID_LENGTH)
  LENGTH=$(echo "$ID_LENGTH" | awk '{print int($1)}')
}

# Handle -e
if [ -z "$LENGTH" ]; then
  # aquire length of the movie
  calculate_movie_length
fi
if [ "$LENGTH" -le 0 ]; then
  BACK_OFFSET=$LENGTH
  calculate_movie_length
  LENGTH=$(($LENGTH+$BACK_OFFSET))
fi
CAPTURE_LEN=$(($LENGTH-$OFFSET))

# if -n is not given...
if [ -z "$NUM_CAPS" ]; then
  # calculate STEPS using INTERVAL
  STEPS=$((${CAPTURE_LEN}/${INTERVAL}))
else
  # calculate INTERVAL using NUM_CAPS
  STEPS=${NUM_CAPS}
  INTERVAL=$((${CAPTURE_LEN}/(${STEPS}-1)))
fi

# construct parameters for scaling
if [ -n "$WIDTH" ]; then
  eval $(mplayer -vo null -ao null -frames 0 -identify "${MOVIEFILENAME}" 2> /dev/null | grep ID_VIDEO_WIDTH)
  VIDEO_WIDTH=$(echo "$ID_VIDEO_WIDTH" | awk '{print int($1)}')
  SCALE_FACTOR=$(echo "scale=5; $WIDTH / ($VIDEO_WIDTH * $NUM_COLS)" | bc)
fi
if [ "${SCALE_FACTOR}" = "1" ]; then
  SCALE_OPTS=""
  FFMPEG_SCALE_OPTS=""
else
  SCALE_OPTS="-sws 2 -vf scale -xy ${SCALE_FACTOR} -zoom"
  FFMPEG_SCALE_OPTS="-sws_flags bicubic -vf scale=iw*${SCALE_FACTOR}:-1"
fi

## End: Argument Parsing

# Helper for stylish progress bar
print_progress () {
  local current=$1
  local total=$2
  local width=30
  local percent=$(( current * 100 / total ))
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))

  # ANSI color escape codes
  local bold="\033[1m"
  local cyan="\033[36m"
  local green="\033[32m"
  local dim="\033[90m"
  local reset="\033[0m"

  local filled_bar=""
  if [ "$filled" -gt 0 ]; then
    printf -v filled_bar '%*s' "$filled" ''
    filled_bar="${filled_bar// /█}"
  fi

  local empty_bar=""
  if [ "$empty" -gt 0 ]; then
    printf -v empty_bar '%*s' "$empty" ''
    empty_bar="${empty_bar// /░}"
  fi

  printf "\r  ${cyan}🎬 Progress:${reset} [${green}%s${dim}%s${reset}] ${bold}%3d%%${reset} (%d/%d)" "$filled_bar" "$empty_bar" "$percent" "$current" "$total"
}

# Worker function for parallel frame extraction & processing
process_frame () {
  local i=$1
  local WORK_DIR

  WORK_DIR=$(mktemp -d "${CAPTURE_DIR}/.tmp_cap_${i}_XXXXXX")
  cd "$WORK_DIR" || return 1

  # extract picture from movie with mplayer (fastest)
  mplayer -nosound -ao null -vo png -ss $(($OFFSET+$i*$INTERVAL)) -frames 1 $SCALE_OPTS "${MOVIEFILENAME}" > /dev/null 2> /dev/null
  if [ -f 00000001.png ]; then
    mv 00000001.png tmp_frame.png
  else
    # ffmpeg fallback
    ffmpeg -ss $(($OFFSET+$i*$INTERVAL)) -r 1 -t 1 -i "${MOVIEFILENAME}" $FFMPEG_SCALE_OPTS tmp_frame.png 2> /dev/null
  fi

  if [ ! -f tmp_frame.png ]; then
    cd "${CAPTURE_DIR}"
    rm -rf "$WORK_DIR"
    return 1
  fi

  local FNAME
  FNAME=$(printf "%s%08d.png" "${PREFIX}" "$i")

  local MAGICK_OPTS=()
  if [ -n "$CROP_SPEC" ]; then
    MAGICK_OPTS+=(-crop "$CROP_SPEC")
  fi
  if [ -n "$AUTOCROP" ]; then
    MAGICK_OPTS+=(-fuzz "10%" -trim)
  fi

  if [ -z "$NO_TIMESTAMPS" ]; then
    local POSITION=$(($OFFSET+$i*$INTERVAL))
    local TIMESTAMP=$(printf "%02d:%02d:%02d" $((($POSITION/3600)%24)) $((($POSITION/60)%60)) $(($POSITION%60)))
    MAGICK_OPTS+=(
      -font "/System/Library/Fonts/Helvetica.ttc"
      -gravity SouthWest
      -pointsize "$FONTSIZE"
      -stroke '#000' -strokewidth 2 -annotate +1-1 "$TIMESTAMP"
      -stroke none -fill '#fff' -annotate +1-1 "$TIMESTAMP"
    )
  fi

  if [ ${#MAGICK_OPTS[@]} -gt 0 ]; then
    magick tmp_frame.png "${MAGICK_OPTS[@]}" "${CAPTURE_DIR}/$FNAME"
  else
    mv tmp_frame.png "${CAPTURE_DIR}/$FNAME"
  fi

  cd "${CAPTURE_DIR}"
  rm -rf "$WORK_DIR"
  echo "1" >> "$PROGRESS_FILE"
}

# Determine CPU core count for parallelism
MAX_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
PROGRESS_FILE=$(mktemp "${CAPTURE_DIR}/.progress_XXXXXX")

cd "${CAPTURE_DIR}"
echo "Making $STEPS screencaps in parallel ($MAX_JOBS jobs), beginning at $OFFSET seconds and stopping at $LENGTH seconds: "
print_progress 0 "$STEPS"

for ((i=0; i<STEPS; i++))
do
  process_frame "$i" &

  while [ $(jobs -r -p | wc -l) -ge "$MAX_JOBS" ]; do
    sleep 0.05
    COMPLETED=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
    print_progress "$COMPLETED" "$STEPS"
  done
done

while [ $(jobs -r -p | wc -l) -gt 0 ]; do
  sleep 0.05
  COMPLETED=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
  print_progress "$COMPLETED" "$STEPS"
done

wait
COMPLETED=$(wc -l < "$PROGRESS_FILE" 2>/dev/null || echo 0)
print_progress "$STEPS" "$STEPS"
echo -e "\n  ✨ Done!"

rm -f "$PROGRESS_FILE"

# Collect output files
SCREENCAPS=()
for ((i=0; i<STEPS; i++)); do
  FNAME=$(printf "%s%08d.png" "${PREFIX}" "$i")
  if [ -f "$FNAME" ]; then
    SCREENCAPS+=("$FNAME")
  else
    echo -e "\nError: Missing screencap $FNAME"
    if [ ${#SCREENCAPS[@]} -gt 0 ]; then
      rm -f "${SCREENCAPS[@]}"
    fi
    exit 5
  fi
done

if [ -n "$DO_PAUSE" ]; then
  echo "Waiting (as requested). Press Enter to continue."
  read
fi

# Strip the extension from the movie's filename and append .avif
MONTAGE_FILE="${MOVIEFILENAME%.*}.avif"

TMP_MONTAGE="tmp_montage_$$.png"

montage \
  -font "/System/Library/Fonts/Helvetica.ttc" \
  -geometry +0+0 \
  -tile ${NUM_COLS}x "${SCREENCAPS[@]}" "$TMP_MONTAGE"

magick "$TMP_MONTAGE" -colorspace sRGB -quality 65 "$MONTAGE_FILE"
rm -f "$TMP_MONTAGE"

# Delete the screen captures
if [ -z "$DO_NOT_DELETE_CAPS" ] ; then
  if [ ${#SCREENCAPS[@]} -gt 0 ]; then
    rm "${SCREENCAPS[@]}"
  fi
fi

cd "${EXEC_DIR}"
