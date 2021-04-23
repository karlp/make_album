#!/bin/sh
# convert any movie down into two constrained size web compatible files, on mp4 and on ogv.
# now you need the details from: http://camendesign.com/code/video_for_everybody
DO_OGV=no
DO_MP4=no
DO_WEBM=no

usage() {
    printf "%s -i input_file -o output_file_basename [options]\n" "$0"
    printf "\t-g\tEnable OGV creation (output to basename.ogv)\n"
    printf "\t-m\tEnable MP4 creation (output to basename.mp4)\n"
    printf "\t-w\tEnable WEBM creation (output to basename.webm)\n"
}

while getopts "i:o:ghmw" c
do
    case $c in
    i) INFILE=$OPTARG ;;
    o) OUTFILE=$OPTARG;;
    g) DO_OGV=yes;;
    m) DO_MP4=yes;;
    w) DO_WEBM=yes;;
    h|*) usage;;
    esac
done


if [ -z "$INFILE" ]
then
    echo "No input file given!"
    exit 1
fi

if [ -z "$OUTFILE" ]
then
    echo "No output file given!"
    exit 1
fi


mk_ogv() {
    ifn="$1"
    ofn="$2".ogv
    [ -e "$ofn" ] && {
        printf "Output file %s already exists, skipping.\n" "$ofn"
        return 1
    }
    ffmpeg -i "$ifn" -codec:v libtheora -qscale:v 7 -codec:a libvorbis -qscale:a 2 -filter_complex "scale=iw*min(1\,min(1280/iw\,720/ih)):-1" "$ofn"
}

mk_webm() {
    ifn="$1"
    ofn="$2".webm
    [ -e "$ofn" ] && {
        printf "Output file %s already exists, skipping.\n" "$ofn"
        return 1
    }
    #ffmpeg -i "$ifn" -vcodec libvpx -acodec libvorbis -filter_complex "scale=iw*min(1\,min(1280/iw\,720/ih)):-1" "$ofn"
    #ffmpeg -i "$ifn" -vcodec libvpx-vp9 -acodec libvorbis -filter_complex "scale=iw*min(1\,min(1280/iw\,720/ih)):-1" "$ofn"

    ffmpeg -i "$ifn" -c:v libvpx-vp9 -b:v 2M -pass 1 -an -f null /dev/null && \
    ffmpeg -i "$ifn" -c:v libvpx-vp9 -b:v 2M -pass 2 -c:a libopus "$ofn"
}

mk_mp4() {
    ifn="$1"
    ofn="$2".mp4
    [ -e "$ofn" ] && {
        printf "Output file %s already exists, skipping.\n" "$ofn"
        return 1
    }
    HandBrakeCLI --no-dvdnav --preset "HQ 720p30 Surround"  -O --two-pass --turbo --input "$ifn" --output "$ofn"
}

[ $DO_OGV = "yes" ] && mk_ogv $INFILE $OUTFILE
[ $DO_MP4 = "yes" ] && mk_mp4 $INFILE $OUTFILE
[ $DO_WEBM = "yes" ] && mk_webm $INFILE $OUTFILE

exit 0;