#!/bin/sh
# convert any movie down into two constrained size web compatible files, on mp4 and on ogv.
# now you need the details from: http://camendesign.com/code/video_for_everybody

INFILE=$1
OUTFILE_MP4=$2
OUTFILE_OGV=$3

if [ -z "$INFILE" ]
then
    echo "Usage is <program> <infile> [outfile]"
    echo "outfile will default if not given, and will never overwrite"
    exit
fi

if [ ! -e "$INFILE" ]
then
    echo "$INFILE doesn't exist!" 
    exit
fi

if [ -z "$OUTFILE_MP4" ] 
then
    OUTFILE_MP4=${INFILE}.mp4
    echo "Defaulting mp4 output to: $OUTFILE_MP4";
fi

if [ -z "$OUTFILE_OGV" ]
then
    OUTFILE_OGV=${INFILE}.ogv
    echo "Defaulting ogv output to: $OUTFILE_OGV";
fi

if [ ! -e "$OUTFILE_OGV" ]
then
    echo "Generating web ogv file: $OUTFILE_OGV";
#    ffmpeg2theora --two-pass --optimize --videoquality 6 --audioquality 1 --max_size 640x640 "$INFILE" -o "$OUTFILE_OGV"
    # from: http://superuser.com/a/794924/138276
    ffmpeg -i "$INFILE" -codec:v libtheora -qscale:v 7 -codec:a libvorbis -qscale:a 2 \
	-filter_complex "scale=iw*min(1\,min(960/iw\,540/ih)):-1" "$OUTFILE_OGV"
else
    echo "$OUTFILE_OGV already exists, refusing to trample!"
fi
if [ ! -e "$OUTFILE_MP4" ]
then
    echo "Generating web mp4 file: $OUTFILE_MP4";
    #HandBrakeCLI --preset "Classic"  --width 640 -X 640 -vb 600 --input "$INFILE" --output "$OUTFILE_MP4"
    # fuck knows what the difference is.
    #HandBrakeCLI --preset "Normal"  --width 640 -X 640 -vb 600 --two-pass --turbo --input "$INFILE" --output "$OUTFILE_MP4"
    # this forces it to only 480 wide, but qt is too high on cpu anyway, so that's ok. (width settings are ignored with this preset)
    HandBrakeCLI --no-dvdnav --preset "iPhone & iPod Touch"  -O -vb 600 --two-pass --turbo --input "$INFILE" --output "$OUTFILE_MP4"
else
    echo "$OUTFILE_MP4 already exists, refusing to trample!"
fi

# maximum compatibility
# TODO: these video sizes might be a bit big?
# iphone forces to max 480 wide  :(
#HandBrakeCLI --preset "iPhone & iPod Touch"  -O --width 640 -vb 600 --two-pass --turbo --input "$INFILE" --output "$OUTFILE_MP4"

