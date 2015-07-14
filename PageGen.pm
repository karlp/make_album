package PageGen;

use 5.008;
use strict;
use warnings;
use Carp;
use POSIX;
use File::Basename;
use File::Spec;
use Image::ExifTool;

# All hacks to make PAR/pp work
use Image::ExifTool::Photoshop;
use Image::ExifTool::IPTC;
use Image::ExifTool::PrintIM;
use Image::ExifTool::Pentax;
use Image::ExifTool::Canon;
use Image::ExifTool::FujiFilm;
use Image::ExifTool::Olympus;


my $non_pic_pattern = '(avi|gif|mov|mp4|flv|ogv|mkv|webm)$';  # move up to config when this works....
my $verbose = 1;


require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use PageGen ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
    make_pic_page	
    get_file_caption
    print_shooting_details
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
    make_pic_page	
    get_file_caption
    print_shooting_details
);

our $VERSION = '1.02';


# Preloaded methods go here.

#
# make_pic_page (file) -
#
# Generates a html page containing the image "file", the exif info from file,
# and next and back links for other pictures.
# TODO
# . Make this a public method type thing. So I can generate a page any time.
sub make_pic_page {

    my $file = shift;
    my %opt = %{$_[0]};
    my $pichtmldir = $opt{"pichtmldir"} || "pichtml";
    my $prevfile = $opt{"prevfile"};
    my $nextfile = $opt{"nextfile"};
    my $style = $opt{"css"};
    my $style2 = $opt{"css2"};

    # First off, make a webpage that displays the picture, we'll
    # HTML::Template this later I think
    my $basename;
    my $nonPicture = "false";
    if ($file =~/$non_pic_pattern/i) {
        $basename = basename($file);
        $nonPicture = "true";
    } else {
        $basename = basename($file, ".jpg");
    }
    my $page = "$basename.html";
    $opt{"page"} = $page;
    mkdir $pichtmldir unless (-e $pichtmldir);
    if ((-e $pichtmldir) and (not -d $pichtmldir)) {
        croak "Output dir exists but is not a directory!";
    }
    my $tmpfn = File::Spec->catfile($pichtmldir, $page);

    open PH, ">$tmpfn";

    # get the current file handle and save it for later
    my $save_fh = select;
    select PH;

    if ($nonPicture ne "false") {
        make_video_page($file, \%opt);
    } else {
        make_pic_page_inner($file, \%opt);
    }

    print "\n</body>\n</html>";
    close PH;
    select $save_fh;
}


sub make_pic_page_inner() {
    my $file = shift;
    my %opt = %{$_[0]};
    my $prevfile = $opt{"prevfile"};
    my $nextfile = $opt{"nextfile"};
    my $style = $opt{"css"};
    my $style2 = $opt{"css2"};
    my $page = $opt{"page"};
    my $file_source = $opt{"file_source"};

    my $comment = $opt{"comment"} || "No comment in file";
    print '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">';
    print '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">';
    print "<head>";
    print "<link rel='StyleSheet' href='$style' type='text/css'/>";
    print "<link rel='StyleSheet' href='$style2' type='text/css'/>";
    print "\n<title>$comment - Large View ($file)</title>\n";
# Has some bugs in graciously playing with existing hot keys....
#   print "\n<script type='text/javascript' src='http://code.jquery.com/jquery-1.4.2.min.js'></script>";
#   print "\n<script type='text/javascript' src='/pics2/extra.js'></script>";
#   print <<HERE;
#\n<script type='text/javascript'> 
#   \$(document).ready(function(){
#     bindHotKeys();
#   });
# </script>
#HERE

    print "</head><body>\n";
    print_nav_links($prevfile, $nextfile);

    print "\n<h2>$comment</h2>";
    my ($pic_basename, $path, $suffix) = fileparse($file);

    my $exif = Image::ExifTool::ImageInfo($file);
    if (my $error = $exif->{Error}) {
        close PH;
        croak "Can't parse $file : $error\n";
    }
    my $width = $exif->{ImageWidth};
    my $height = $exif->{ImageHeight};
    print <<HERE;
	<div class="embed-container">
		<img src="../$pic_basename" alt="$comment"/>
	</div>
HERE
    print_nav_links($prevfile, $nextfile);
    if ($file =~ /pano/) {
        print_pano_details($file_source);
    } else {
        print_shooting_details($file_source);
    }
    print_share_fb();
    print_cc_details($page, $comment, \%opt);
    print_scripts();
}


sub make_video_page() {
    my $infile = shift;
    my %opt = %{$_[0]};
    my $pichtmldir = $opt{"pichtmldir"} || "pichtml";
    my $prevfile = $opt{"prevfile"};
    my $nextfile = $opt{"nextfile"};
    my $style = $opt{"css"};
    my $style2 = $opt{"css2"};
    my $page = $opt{"page"};


    print STDOUT "getting filecaption for $infile\n" if $verbose;
    my $captionFile;
    if ($infile =~ /ogv$/i) {
        $captionFile = $infile;
    } else {
        $captionFile = "$infile.ogv";
    }
    my $comment = $opt{"comment"} || get_file_caption("$captionFile");
    my $file = basename($infile);

    my ($mp4file, $ogvfile);
    if ($file =~ /ogv$/i) {
        print STDOUT "input video is ogv, assuming split pair: $file\n" if $verbose;
        $ogvfile = $file;
        $file =~ s/ogv$//i;  # Strip ogv off to get back to .avi or .mkv...
        $mp4file = $ogvfile;
        $mp4file =~ s/ogv$/mp4/i;
    } else {
        $ogvfile = "$file.ogv";
        $mp4file = "$file.mp4";
    }
        

    print '<!DOCTYPE HTML>';
    print "<html>";
    print "<head>";
    print "<link rel=\"StyleSheet\" href=\"$style\" type=\"text/css\"/>";
    print "<link rel=\"StyleSheet\" href=\"$style2\" type=\"text/css\"/>";
    print "\n<title>$comment - Large View ($file)</title>\n";
    print "</head><body>\n";

    print_nav_links($prevfile, $nextfile);
    print "\n<h2>$comment</h2>";

# we'll set preload, because, well, they had to click to get to this page!

    ## FIXME - XXX need to be able to decide whether we are remaking (and so
    # already have both videos, and need to change suffix, or add suffix)
    print <<HERE;
<video width="640" height="360" controls="controls" preload>
    <source src="../$ogvfile" type="video/ogg" />
    <source src="../$mp4file" type="video/mp4" /><!--[if gt IE 6]>
    <object width="640" height="375" classid="clsid:02BF25D5-8C17-4B23-BC80-D3488ABDDC6B"><!
    [endif]--><!--[if !IE]><!-->
    <object width="640" height="375" type="video/quicktime" data="../$mp4file"><!--<![endif]-->
    <param name="src" value="../$mp4file" />
    <param name="autoplay" value="false" />
    <param name="showlogo" value="false" />
        <p>
            <img src="../thumbs/TN_$file.jpg" alt="\$comment\"/>
        </p>
        <p>
            <strong>No video playback capabilities detected.</strong>
            Try clicking one of these links instead, which might work for you.<br/>
            <a href="../$mp4file">MPEG4 / H.264 ".mp4" (Internet Explorer/Quicktime)</a> |
            <a href="../$ogvfile">Ogg Theora &amp; Vorbis ".ogv" (higher res, more open format)</a>
        </p>
    <!--[if gt IE 6]><!-->
    </object><!--<![endif]-->
</video>
HERE

    print_video_details($infile);

    print_share_fb();
    print_cc_details($page, $comment, \%opt);
}

sub print_nav_links() {
    my $prevfile = shift;
    my $nextfile = shift;
    
    print "<div>\n<ul class=\"pagination\">";
    if (defined $prevfile) {
        # if there's no .jpg on the end, doesn't remove it :)
        $prevfile = basename($prevfile, ".jpg");
        print "<li class=\"pagination-prev\"><a href=\"$prevfile.html\" id=\"prevfile\">&#8592; Prev</a></li>\n";
    }
    print "<li class=\"pagination-up\"><a href=\"../\" id=\"upfile\">Up</a></li>\n";
    if (defined $nextfile) {
        $nextfile = basename($nextfile, ".jpg");
        print "<li class=\"pagination-next\"><a href=\"$nextfile.html\" id=\"nextfile\">Next &#8594;</a></li>\n";
    }
    print "</ul>\n</div><div style=\"clear:both;\"></div>\n";
}



# Returns undefined if there's no caption, so this can be a clean utility, rather than imposing external behaviours
sub get_file_caption {
    my $file = shift;
    # Get IPTC header
    my $et = new Image::ExifTool;
    my $info = $et->ImageInfo($file);
    my $rawCaption = 
                        $et->GetValue("Title", Group=>"XMP") ||
                        $et->GetValue("Title", Group=>"Matroska") ||
                        $et->GetValue("Caption-Abstract") ||
                        $et->GetValue("Description", Group=>"XMP") ||
                        $et->GetValue("UserComment");
    my $printCaption = "";
    $printCaption = $rawCaption if (defined $rawCaption);
    print STDOUT "PageGen: filecaption for $file is '$printCaption'\n" if $verbose;
    return $rawCaption;
}

# file is the relative path back to the current document.
sub print_cc_details() {
    my $file = shift;
    my $title = shift;
    my %opt = %{$_[0]};
    my $creativeCommons = $opt{"creativeCommons"};
    my $creativeCommonsTitle = $opt{"creativeCommonsTitle"};
    my $creativeCommonsEmail = $opt{"creativeCommonsEmail"};
    my $creativeCommonsName = $opt{"creativeCommonsName"};


    if ($creativeCommons ne "false") {
        print "\n\n";
        print <<HERE;
        <div id="creativeCommons">
<a rel="license" href="http://creativecommons.org/licenses/$creativeCommons/">
<img alt="Creative Commons License" style="border-width:0"
src="http://i.creativecommons.org/l/$creativeCommons/88x31.png" width="88" height="31" />
</a><br />
<em>$title</em>, by $creativeCommonsName
   is licensed under a <a rel="license" href="http://creativecommons.org/licenses/$creativeCommons/">$creativeCommonsTitle</a>.
<br />Permissions beyond the scope of this license may be available at <a href="mailto:$creativeCommonsEmail" rel="cc:morePermissions">$creativeCommonsEmail</a>.
    </div>
HERE
    }

}
    

sub print_share_fb() {
    print <<FB_SHARE;
    <div id="sharing"><em>Sharing: </em>
<script type="text/javascript">function fbs_click()
    {u=location.href;t=document.title;window.open('http://www.facebook.com/sharer.php?u='+encodeURIComponent(u)+'&amp;t='+encodeURIComponent(t),'sharer','toolbar=0,status=0,width=626,height=436');return
    false;}</script><a href="http://www.facebook.com/share.php?u=&lt;url>" onclick="return fbs_click()"
    target="_blank"><img src="http://static.ak.fbcdn.net/rsrc.php/z39E0/hash/ya8q506x.gif" alt="share on
    facebook" width="16" height="16"/></a><br/>
    </div>
FB_SHARE
}

sub print_pano_details ($) {
    my $file = shift;
    my $exif = Image::ExifTool::ImageInfo($file);
    if (my $error = $exif->{Error}) {
        close PH;
        croak "Can't parse $file : $error\n";
    }
    my $date = $exif->{DateTimeOriginal} ||  $exif->{DateCreated} || "Bad camera!";
    # Start printing it all out
    print "<p><br/><em>Panoramic image! scroll sideways!</em></p>\n";
    print "<h3>Shooting Details</h3>\n";
    printf "<p>Date Taken: %s<br/>\n", $date;
    print "This is stitched panorama of multiple images, cut and cropped and possibly edited for effect.";
    print " No shooting details would be relevant here.";
}

sub print_video_details ($) {
    my $file = shift;
    my $filename = basename($file);
    my $captionFile;
    if ($file =~ /ogv$/i) {
        $captionFile = $file;
    } else {
        $captionFile = "$file.ogv";
    }
    my $exif = Image::ExifTool::ImageInfo("$captionFile"); # FIXME - should we fall back?
    if (my $error = $exif->{Error}) {
        close PH;
        croak "Can't parse $file : $error\n";
    }
    my $date = $exif->{CreateDate} || "Bad file info!";
    my $filesize = $exif->{FileSize};
    print "<h3>File Details</h3>\n";
    printf "<p>Date Created: %s<br/>\n", $date;
    printf "File size: %s<br/>\n", $filesize;
    printf "<p>Direct Download: <a href='../$filename.mp4'>MP4</a> or <a href='../$filename.ogv'>OGV</a></p>";


}

sub print_scripts() {

	print <<HERE;
<script src="/js/keyboard-pagination.min.js"></script>
<script type="text/javascript">
keyboardPagination( '.pagination',
{
    prev: '.pagination-prev',
    next: '.pagination-next',
    up: '.pagination-up'
});
</script>
HERE

}



sub print_shooting_details ($) {
    my $file = shift;

    # Get exif data, and start processing!
    my $exif = Image::ExifTool::ImageInfo($file);
    if (my $error = $exif->{Error}) {
        close PH;
        croak "Can't parse $file : $error\n";
    }

    my $model = $exif->{Model} || "Unknown Camera";
    my $owner = $exif->{OwnerName} ||  "Unset";
    
    # Handle zooms as well as primes
    my $lens_long = $exif->{"LongFocal"};
    my $lens_short = $exif->{"ShortFocal"};
    my $lens_raw = $exif->{"Lens"};
    my $lens;
    if (defined $lens_raw) {
        # then let's just use it, and we're done....
        $lens = $lens_raw;
    } else {
        
        unless ((defined $lens_long) and (defined $lens_short)) {
    	    #this is a bit canon specific :)  so instead, let's assume it's all zooms
            $lens = "Zoom";
        } else {
            if ($lens_long == $lens_short) {
                $lens = "Fixed";
            } else {
                # So it's a zoom, but we need to check whether it's measured in mm
                # or not.  some cameras don't measure in mm.  God knows why :)
                my $units_per_mm = $exif->{"FocalUnits"} || 1;
                $lens_short /= $units_per_mm;
                $lens_long /= $units_per_mm;
                $lens = sprintf "%d-%d mm", floor($lens_short), floor($lens_long);
            }
        }
    }
    
    my $focal = $exif->{"FocalLength"};
    if (defined($focal)) {
        my $temp = $focal;
        $temp =~ s/mm//;
        my $scale;
        if ($model =~ /REBEL/) {
            $scale = 1.6;
        } else {
            $scale = $exif->{"ScaleFactor35efl"};
        }
        if (defined($scale)) {
            $focal .= sprintf " (35mm equiv %d mm)", floor($temp * $scale);
        }
    } else {
        $focal = "Unknown";
    }
    
    my $shutter = $exif->{ShutterSpeed} || "Unknown";

    my $aperture = $exif->{Aperture} || "Unknown";

    my $iso = $exif->{ISO} || "Unknown";
    
    my $date = $exif->{DateTimeOriginal} ||  $exif->{DateCreated} || "Bad camera!";

    # Start printing it all out
    print "<h3>Shooting Details</h3>\n";
    print "<p>\n";
    # Add a label for art photos, to clearly say that they may not be real
    if ($file =~ /art/) {
        print "Note: this photo has been edited for artistic effect, exif details are from original source
        image<br/>\n";
    } 
    # label and link for stacked photos....
    if ($file =~ /stack/) {
        print "Note: this photo is a <a href=\"/pics2/stack_details.html\">stack of two images</a>, the exif should not be";
        print "considered reliable.<br/>\n";
    }
    printf "Camera: %s (Owner: %s)<br/>\n", $model, $owner;
    printf "Lens: %s @ %s<br/>\n", $lens, $focal;
    printf "Exposure: f/%s &amp; %s sec<br/>\n", $aperture, $shutter;
    printf "Iso: %s<br/>\n", $iso;
    printf "Date Taken: %s<br/>\n", $date; 
    print "</p>";
    #optionally add shooting mode, flash details, metering?
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

PageGen - Perl extension for blah blah blah

=head1 SYNOPSIS

  use PageGen;
  blah blah blah

=head1 ABSTRACT

  This should be the abstract for PageGen.
  The abstract is used when making PPD (Perl Package Description) files.
  If you don't want an ABSTRACT you should also edit Makefile.PL to
  remove the ABSTRACT_FROM option.

=head1 DESCRIPTION

Stub documentation for PageGen, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Karl Palsson, E<lt>karl@c47.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Karl Palsson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
