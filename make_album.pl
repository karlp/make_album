#!/usr/bin/perl -w
# blah
# COPYRIGHT Karl Palsson, 2002, 2003, 2004, 2005

# FIXME - karl, look at http://camendesign.com/code/video_for_everybody

use strict;
#use lib "c:/bin";
my $lib_dir;
BEGIN { $lib_dir = "/home/karlp/src/make_album"; }
use lib $lib_dir;
use Carp;
use PageGen;
use Image::ExifTool; # ugly, seeing as pagegen already depends on it?
use File::Copy;
use File::Basename;
use File::Path;
use File::Slurp;  # Not in the default perl install
use File::Spec;
use File::stat;
use Getopt::Long;
use Pod::Usage;
#use G;

### CONFIG ###
# PUBLIC CONFIG
## FIXME: make the option names more closely reflect the variable names?
my $copyright_global;
my $copyright;
my $text_colour = "orange";
my $font = "c:/bin/arial.ttf";
my $fontsize = 16;
my $quality = 60;
my $stylesheet = "/tweak2.css";
my $stylesheet2 = "/colour-tweak.css";
my $report_file = "tripreport.txt";  # default for karl!
my $config_file = "gallery.metadata";
#use the defaults in PageGen.pm
#my $creativeCommons = "by/3.0"; # other values are "false" or real strings from cc....
my $creativeCommons = "by-nc/3.0"; # other values are "false" or real strings from cc....
#my $creativeCommonsTitle = "Creative Commons Attribution 3.0 Unported License";
my $creativeCommonsTitle = "Creative Commons Attribution-Noncommercial 3.0 Unported License";
my $creativeCommonsEmail = 'sales@tweak.net.au';
my $creativeCommonsName = "Karl Palsson";

# PREFIXES
my $outdir = "album";
my $thumbdir = "thumbs";
my $pichtmldir = "pichtml";
my $wf_prefix = "web";
# Separator is always _ if anyone complains I may change that, but sif
my $thumb_prefix = "TN";
my $thumb_format = "jpg";
my $thumb_dimension = "250";
#my $web_full_to_tn_scale = "250x250>";
my $web_full_to_tn_scale = "${thumb_dimension}x${thumb_dimension}>";
my $non_pic_pattern = "avi|gif|mov|mp4|flv|ogv|mkv";  # move up to config when this works....
my @imagesuffixes = qw/.jpg .png .tif/;
my $videoOverlay = "$lib_dir/overlayPlayIcon.png";
#my $videoOverlay = "/home/karl/bin/make_album.dir/video250.png";

## Config for the index pages
my $colsperrow = 3;
my $rowsperpage = 2;
my $indexbasename = "page";
my $page_title = "Title goes here";
my $reverse_order = 0;
my $gallery_index_link ="/pics2/";   # default for pics2 galleries on tweak

my $verbose = 3;

# Should we resize the originals when we copy them to the output dir?
my $do_resize = "800x800>";
#my $do_resize = "45%";

# Should we draw text on the full sized web images?
my $do_draw = 1;

# Should we just make the html, nothing else?
# fairly useless really, see the docs
my $htmlonly = 0;  

# should we trample everything necessary?  (actually, just forces regen of
# webimages)
my $force = 0;

# Do we just want to make a report, no pictures?  (not really useful, hidden)
my $no_pictures = 0;

# should we filter the list of input files?  (based on iptc publish/captions?)
my $filter_imp = 2; # I use this all the time, so make it the damn default!
#my $filter_imp = 0; # just while I hack on videos
my $filter_cap = 0;


### CSS CONFIG

my $css_story_class = "story";
my $css_thumbnailtable_class = "ma_gallery_table";
my $css_caption_class = "imagecaption";


##### END OF PUBLIC CONFIG ####


my ($help, $man);

# Parse the metadata file first.  this is because we always want command line
# options to override any file options.
# XXX less whitespace stripping hackery would be nice
if (-f $config_file) {
    open(METAFILE, $config_file);
    while (my $line = <METAFILE>) {
        $line =~ s/^\s+|\s+$//gm;  #strip leading, trailing space, plus chomp
        next if ($line eq "");
        next if ($line =~ /^#/);
        my @thisline = split ('=', $line);
        if ($thisline[0] =~ /title/i) {
            $page_title = $thisline[1];
        }
        if ($thisline[0] =~ /outdir/i) {
            $outdir = $thisline[1];
            $outdir =~ s/^\s+|\s+$//gm;  #strip leading, trailing space, plus chomp
        }
    }
}

GetOptions(
    'columns|cols=i' => \$colsperrow,
    'copyright=s' => \$copyright_global,
    'draw!' => \$do_draw,
    'filter_imp=i' => \$filter_imp,
    'filter_cap' => \$filter_cap,
    'font=s' => \$font,
    'force!' => \$force,
    'fontsize=i' => \$fontsize,
    'gallery_index' => \$gallery_index_link,
    'help' => \$help,
    'htmlonly' => \$htmlonly,
    'index_prefix' => \$indexbasename,
    'man' => \$man,
    'noresize' => sub { $do_resize = 0 },
    'nopics' => \$no_pictures,
    'outdir=s' => \$outdir,
    'pichtmldir=s' => \$pichtmldir,
    'prefix=s' => \$wf_prefix,
    'quiet' => sub { $verbose = 0 },
    'quality=i' => \$quality,
    'reportfile=s' => \$report_file,
    'resize=s' => \$do_resize,
    'reverse' => sub {$reverse_order = 1},
    'rows=i' => \$rowsperpage,
    'stylesheet|style|css=s' => \$stylesheet,
    'stylesheet2|style2|css2=s' => \$stylesheet2,
    'text_colour|text_color|colour|color=s' => \$text_colour,
    'thumb_dir=s' => \$thumbdir,
    'thumb_format=s' => \$thumb_format,
    'thumb_prefix=s' => \$thumb_prefix,
    'thumb_size=s' => \$web_full_to_tn_scale,
    'title=s' => \$page_title,
    'verbose' => \$verbose,
    
) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Files on the command line are MANDATORY!  sort of :) 
unless ($no_pictures) {
    pod2usage("$0: No files given.")  if ((@ARGV == 0) && (-t STDIN));
}

my @files;
my $findex = 1;  # Only used for status reporting

##############
# INTERNAL CONFIG
my $tdir = File::Spec->catdir($outdir, $thumbdir);
my $pdir = File::Spec->catdir($outdir, $pichtmldir);

my $file;

# if the outdir doesn't exist, then make one.  
if ((-e $outdir) and (not -d $outdir)) {
    die "Output dir <$outdir> exists, but is not a directory!";
}
unless (-d $outdir) {
    mkpath $outdir;
}

# construct a list of output pictures.  
# (from the full sized web images, not the origs)
# construct a new list of files, that is the full sized web images, not the
# origs
# Fix globbing first  ### XXX shouldn't G fix this?
# At this point, we should only be left with filenames.  options, and invalid options should have been caught earlier.
# doesn't work particularly well with filenames with spaces on unix. but unix people don't use spaces anyway :)
my @elements;
foreach my $arg (@ARGV) {
	if ($arg =~ /\n/) {
		@elements = split /\n/, $arg;
                # might have non-existent elements? FIXME
		push @files, @elements;
	} elsif (-f $arg) {
		push @files, $arg;
	} else {
            print "Skipping non-existant file: $arg\n";
        }
}


# Perhaps we have non-image files that we just want links to, in addition
# to the images?  Let's filter these out first.
# XXX currently this is just by outright removing any avi's from the list
my @non_pic_files = grep (/$non_pic_pattern/i, @files);
my @real_pic_files = grep(!/$non_pic_pattern/i, @files);
#@files = @real_pic_files;

# ok, so perhaps we want to exclude images in the list that don't have an 
# importance

my %sideCaptions;

#ripped from acdc2meta
use MSDOS::Descript;
my $ifile = "descript.ion";
my $descriptIon;
if (-f $ifile) {
    `iconv -f ISO_8859-1 -t UTF-8 $ifile > $ifile.$$`;
    $descriptIon = new MSDOS::Descript("$ifile.$$");
    `rm $ifile.$$`;
} else {
    $descriptIon = new MSDOS::Descript;
}


foreach my $captionReadingFile (@files) {
    my $dcapt = $descriptIon->description($captionReadingFile) if $descriptIon->description($captionReadingFile);
    $sideCaptions{$captionReadingFile} = $dcapt;
}


if ($filter_cap) {
    # I don't use this anymore, but if I did, I would have to fix it for videos too... FIXME
    @files = grep {defined Image::ExifTool::ImageInfo($_)->{"Caption-Abstract"} } @files;
}

# We don't have rankings for any decent metadata for video,
# so count it as important if it has a caption of any sort
sub get_importance_video {
    my $file = shift;
    # for files that we can't embed things in easily... use the description file we had earlier...
    if (defined $sideCaptions{$file}) {
        print "Processed importance for $file: 1\n" if $verbose;
        return 1;
    }
    # or, if it's a mkv or ogv...
    my $ret = 0;
    if ($file =~ /(mkv|ogv)$/) {
        my $et = new Image::ExifTool;
        my $info = $et->ImageInfo($file);
        if (defined $et->GetValue("Error")) {
            print "exiftool can't parse: $file, skipping\n" if $verbose;
        } elsif (defined $et->GetValue("Title")) {
            $ret = 1;
        }
    }
    print "Processed importance for $file: $ret\n" if $verbose;
    return $ret;
}

sub get_importance {
    my $file = shift;
    if ($file =~ /($non_pic_pattern)$/i) {
        return get_importance_video($file);
    }
    my $et = new Image::ExifTool;
    my $info = $et->ImageInfo($file);
    if (defined $et->GetValue("Error")) {
        print "exiftool can't parse: $file, skipping\n" if $verbose;
        return 0;
    }
    my $imp = $et->GetValue("Rating", Group=>"XMP") ||
        $et->GetValue("Urgency#", Group=>"XMP") ||
        $et->GetValue("Urgency#", Group=>"IPTC") ||
        $et->GetValue("Urgency", Group=>"IPTC") ||
        0;
    my $speci = $et->GetValue("SpecialInstructions") || $et->GetValue("Grouping") || "";
    my $ret = (($imp >= $filter_imp) || ($speci =~ /Publish/i ));
    print "Processed importance for $file: $ret\n" if $verbose;
    return $ret;
}

if ($filter_imp) {
    print "Filtering by importance... (this can take a while)\n";
    foreach my $prefile (@files) {
        print "list before importance filtering contains: $prefile\n" if $verbose >= 2;
    }
    @files = grep { get_importance($_) } @files;
    foreach my $afterfile (@files) {
        print "list after importance filtering contains: $afterfile\n" if $verbose >= 2;
    }
}
    

if ($reverse_order) {
    @files = reverse(@files);
}


# need to make this fcount after we remove the nonpics, as this is what 
# is used to determine how many gallery pages there are.
my $fcount = @files;

# @files is the actual files we use as input, @n_files is the output files
my @n_files;
foreach my $n_file (@files) {
    my ($fn, $dir, $suffix) = fileparse($n_file, @imagesuffixes);
    $fn = lc($fn);
    my $tmp_file = File::Spec->catfile($outdir, "${wf_prefix}_${fn}$suffix");
    push @n_files, $tmp_file;
}

# If we just want the html regenned, we leave the filenames intact, and just
# jump to the page gen section. HACK ALERT!
if ($htmlonly) {   # urrh, BUSTED!? This doesn't seem to work
    @n_files = @files;
    goto justhtml;
}


# Make the web versions of the originals
print "Watermarking and resizing originals in output directory: $outdir\n" if $verbose;
foreach $file (@files) {
    # if copyright global was set, we're done, let's go.
    if (defined ($copyright_global)) {
        $copyright = $copyright_global;
    } else {
        # need to determine a per image copyright, or default
        my $cr_try = &determine_copyright($file);
        if (defined ($cr_try) and ($cr_try ne "")) {
            $copyright = $cr_try;
        } else {
            $copyright = "© Karl Palsson";
        }
    }
    
    &make_web_full($file, $do_resize, $do_draw);
    # Don't use old strings on new images!
    undef $copyright;
}

# Make somewhere to put the thumbnails if necessary
if ((-e $tdir) and (not -d $tdir)) {
    die "Thumbnail dir <$tdir> exists, but is not a directory!";
}
mkpath $tdir unless (-d $tdir);


print "Generating thumbs in output directory: $tdir\n" if $verbose;
foreach $file (@n_files) {
    &make_thumb($file);
}

# Make somewhere to put the per pic html
if ((-e $pdir) and (not -d $pdir)) {
    die "Per Picture html dir <$pdir> exists, but is not a directory!";
}
mkpath $pdir unless (-e $pdir);

######################
#
# Make the per picture pages
justhtml: print "Generating per picture HTML files in $outdir/$pichtmldir\n" if $verbose;
my $prevfile = undef;
my $loop = 1;
foreach $file (@n_files) {
    my $nextfile = $n_files[$loop];
    my %options = (
        pichtmldir => $pdir,
        prevfile => $prevfile, 
        nextfile => $nextfile,
        css => $stylesheet,
        css2 => $stylesheet2,
        creativeCommons => $creativeCommons,
        creativeCommonsTitle => $creativeCommonsTitle,
        creativeCommonsName => $creativeCommonsName,
        creativeCommonsEmail => $creativeCommonsEmail,
        comment => $sideCaptions{$files[$loop - 1]}
    );
    make_pic_page($file, \%options);
    $loop++;
    $prevfile = $file;
}

#################
# 
# Make the index pages

print "Generating front index HTML files in $outdir\n" if $verbose;
$loop = 0;
my $currpage = 1;
my $currrow = 0;
my $picsperpage = $colsperrow * $rowsperpage;
my $picsleft = $fcount;

our $totalpages = int(($fcount / $picsperpage)); 
unless (($fcount % $picsperpage) == 0) {
    $totalpages++;
}


sub doclose () {
    print "</table>";
    dolinks();  # Would like this here, but currpage has been incremented outside our control
    print "\n</div></body>";
    print "</html>";
}

sub dolinks () {
    my $i = 1;
    if ($totalpages > 1) {
        for ($i = 1; $i <= $totalpages; $i++){
            if ($i == $currpage) {
                print "page $i ";
            } else {
                print "<a href=\"$indexbasename"."_$i.html\">page $i</a> ";
            }
        }
    }
}	
    

sub doheader () {
    print "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\n";
    print "<html>";
    print "<head>\n";
    print "<link rel=\"StyleSheet\" href=\"$stylesheet2\" type=\"text/css\">\n";
    print "<link rel=\"StyleSheet\" href=\"$stylesheet\" type=\"text/css\">\n";
    $page_title =~ s/&/&amp;/g;
    print "<title>$page_title</title>\n";
    print "</head>\n";

    print "<body><div class=\"main\">";
    if ($gallery_index_link) {
        print "<p><a href=\"$gallery_index_link\">Up to index</a>\n";
    }
    print "<h2>$page_title</h2><hr>\n";
    # also need links to all the pages, and a placeholder for ours here
    
    if ($currpage == 1) {
	if ($report_file and -f $report_file) {
            print "<p><em>Pictures are at the bottom...</em></p>";
            my $report = read_file($report_file);
            print "<div class=\"$css_story_class\">";
	    print $report;
            print "</div>";
	}
	if (@non_pic_files) {
	    #do_nonpictures();  # we don't want this shit old way any more
	}
        print "<hr>";
    }
    dolinks();
    
    print "\n<table class=\"$css_thumbnailtable_class\">";
}
    

# open the first file here, the rest will be opened internally
#my $filename = "$htmlbasename"."_$currpage.html";
# XXX work out a neat way of zeropadding $currpage
my $fhname = File::Spec->catfile($outdir, "$indexbasename"."_$currpage.html");
open FH, ">$fhname";
select FH;

doheader();

foreach $file (@n_files) {
    my $basename = basename($file, @imagesuffixes);
    $basename = basename($basename, ".ogv");

    my $comment = get_file_caption($file) 
                || get_file_caption("$file.ogv")
                || $sideCaptions{$files[$loop]} 
                || "no comment in file";

    print "\n<tr>" if (($loop == 0) && ($currrow == 0));
    print "\n<td>";
    my $thumb_fname = "$thumbdir/${thumb_prefix}_$basename.$thumb_format";
    my $exif = Image::ExifTool::ImageInfo("$outdir/$thumb_fname");
    if (my $error = $exif->{Error}) {
        close PH;
        croak "Can't parse $outdir/$thumb_fname : $error\n";
    }
    my $width = $exif->{ImageWidth};
    my $height = $exif->{ImageHeight};

    print "<a href=\"$pichtmldir/$basename.html\">";
    print "<img src=\"${thumb_fname}\" alt=\"$comment\" ";
    print "width=\"$width\" height=\"$height\"></a>";
    print "<p class=\"$css_caption_class\">$comment</p>";
    $picsleft--;
    $loop++;
    #time for a new row
    if (($loop % $colsperrow) == 0) {
        print "\n\n\n</tr>";
        $currrow++;
        #time to start a new page
        if (($currrow == $rowsperpage) && ($picsleft > 0)) {
            doclose();
            $currpage++;
            close FH;
            $fhname = File::Spec->catfile($outdir, "$indexbasename"."_$currpage.html");
            open FH, ">$fhname";
            select FH;
            doheader();
            $currrow = 0;
        } else {
            print "\n<tr>";
        }
    }
}
doclose();


################# END ######################

sub make_thumb ($) {
    my $file = shift;

    # Thumbs are always clobberred. they're easy to regen, and contain no info
    # karl, you silly boy, you don't even follow your comments!

    printf "making thumb for $file\n";
    if ($file =~ /($non_pic_pattern)$/i) {
        # Make a thumbnail of this video?
        my $basename = basename($file); # FIXME - strip off the suffix...
        my $ofile = File::Spec->catfile($tdir, "${thumb_prefix}_$basename");
        `ffmpegthumbnailer -i "$file.mp4" -s $thumb_dimension -o "$ofile.$thumb_format"`;  # just pick one of the video outs
        `convert "$ofile.$thumb_format" $videoOverlay -gravity center -composite -thumbnail \"$web_full_to_tn_scale\"  "$ofile.$thumb_format"`; # resize to standard thumbnail size....
    } else {
    
    # Work out a new name for writing
    my $basename = basename($file, @imagesuffixes);
    my $ofile = File::Spec->catfile($tdir, "${thumb_prefix}_$basename.$thumb_format");
#    if (-e $ofile) {
#        if ($verbose) {
#            print "$ofile skipped, it already exists\n";
#        }
#        return;
#    }

    `convert "$file"  -thumbnail \"$web_full_to_tn_scale\"  "$ofile"`;
    }
    
}

sub make_web_full ($) {
    my $file = shift;
    my ($do_resize, $do_draw) = @_;
    print "Making webfull for $file\n";

    #make new filename for output
    my $lcfile = lc($file);
    
    if ($lcfile =~ /$non_pic_pattern/i) {
        # thumbnails were already made of the source, but now we need the proper output videos...
        my $basename = basename($lcfile); # FIXME - strip off the suffix...
        my $ofile_mp4 = File::Spec->catfile($outdir, "${wf_prefix}_$basename.mp4");
        my $ofile_ogv = File::Spec->catfile($outdir, "${wf_prefix}_$basename.ogv");
        `/home/karlp/bin/make_web_videos.sh "$file" "$ofile_mp4" "$ofile_ogv"`;
    } else {
    my $basename = basename($lcfile, @imagesuffixes);
    my $ofile = File::Spec->catfile($outdir, "${wf_prefix}_$basename.jpg");

    # If outfile already exists, skip it.
    if ((-e $ofile) and (!($force))) {
        print "$ofile skipped, it already exists\n" if $verbose;
        $findex++;
        return;
    }

    # fiddle with the resizing for special images....
    # any file with "pano" in the name gets resized to 800 high, rather than max side of 800,
    # NOTE: this blatantly overrides the $do_resize variable, also see PageGen for where the details are modified
    if ($file  =~ /pano/) {
        $do_resize = "x800";
    }
    
    my $cmd = "convert \"$file\" -quality $quality -gravity SouthEast";
    $cmd .= " -resize \"$do_resize\"" if $do_resize;
    if (-e $font) { $cmd .= " -font $font"; }
    $cmd .= " -fill $text_colour";
    $cmd .= " -draw \"text 10,10 '$copyright'\"" if $do_draw and $copyright;

    $cmd .= " \"$ofile\"";

    `$cmd`;
    }  # end of else (for jpgs)

    print "File $findex/$fcount ($file) completed\n" if $verbose;
    $findex++;
}

# copy the non_picture files over to the outdir, and print a list of links
sub do_nonpictures () {
    print "<h4>Non-picture files included in this gallery</h4>";
    foreach my $npf (@non_pic_files) {
	my $ofile = File::Spec->catfile($outdir, $npf);
	copy($npf, $ofile);
	my $bnf = basename($npf);
	print "<a href=\"$bnf\">$bnf</a>";
	my $fsz = stat($npf)->size;
	printf " Size: %d KB<br>", $fsz / 1024;
    }
    print "<hr>";
}

# try and put together a copyright string appropriate for this image
# a bit hacky
sub determine_copyright () {
    my $fn = shift;
    my $info = Image::ExifTool::ImageInfo($fn);
    my $person = $info->{"CopyrightNotice"};
    unless (defined($person)) {
        $person = $info->{"OwnerName"};
    }
    
    my $year = $info->{'DateTimeOriginal'};
    if (defined($year)) {
        $year =~ s/:.*//;
    }

    if (defined($person) and defined($year)) {
        return "$person, $year";
    } elsif (defined($person)) {
        return "$person";
    } elsif (defined($year)) {
        return "$year";
    }
}
    

__END__

=head1 NAME

make_album - Perl script to generate nice[1] webpages for digicam pictures

=head1 SYNOPSIS

  make_album *.jpg --verbose
  make_album --filter_cap *.JPG
  make_album `cat goodfiles.txt`
  make_album *.jpg --outdir /web/pics/my_event --title "My Event pics"
  make_album --help

=head1 ABSTRACT

  Given a list of jpgs on the command line, resizes and annotates the
  files, generates thumbnails, a per picture html page containing 
  shooting details and IPTC comments, and a front index page showing
  the thumbnails.  The front index page is actually a page_1,page_2
  type deal, with only a limited number of pictures per page.

=head1 DESCRIPTION

Need to add lots here, desribing more of the motivation I guess?  more usage
examples?  I think I've covered all the command line options in the
documentation here.  To modify the defaults, edit the source file, all the
config options are at the top of the script

=head1 OPTIONS

=over 8

=item B<--columns --cols num> I<(default 3)>

Number of columns per row for thumbnails on the index page

=item B<--copyright text> I<(default nothing)>

This text is drawn on the output pictures as a copyright notice.
This has absolute precendence.  The default behaviour is to try and construct
a copyright notice based on the "CopyrightNotice" field in the IPTC together
with the image exif datestamp.  If no CopyrightNotice field is found, the
OwnerName Makernote is used (if available)

My cameras have OwnerName set, so this "Just works" for me, you may wish to
fiddle with this if not.

=item B<--draw>

Pictures have a copyright text drawn on them when copying to the output dir

=item B<--filter_cap> I<(default off)>

Filter the list of input pictures to only include those that have an IPTC
caption field.

Using this in combination with --filter_imp could have unexpected results

=item B<--filter_imp=number> I<(default 2, ie on)>

Filters the list of input pictures to only include those that have an IPTC
urgency field greater than or equal to this number.  This also includes files that have "Publish" in the special instructions field.

Using this in combination with --filter_cap could have unexpected results

=item B<--font fontname>

Specifies the font to use when drawing copyright text on pictures.

=item B<--fontsize integer> I<(default 16)>

Specifies the font size to use when drawing copyright texts

=item B<--force> I<(default no)>

Should output files be overwritten if they already exist or not

=item B<--gallery_index> I<(default ../../../)>

Should a link to a parent index page of the galleries be added, and if so,
where is that index located.  (this is a href link)

=item B<--help>

Print a brief help message and exits.

=item B<--htmlonly>

Just make the HTML pages, the per page, and the index pages.  Assume all the
pictures and thumbnails are generated and in the right format, you would normally use --outdir . with this option.

Note, that it will generate the per page html from the existing images, so if you've changed the caption for instance,
nothing changes.  This is only useful if you have just updated the trip report, title, or are adding pictures, that
sort of thing.  See I<force>

=item B<--index_prefix> I<(default page)>

Specifies the basename to use for the index pages.  In the default setup, the pages will be page_01.html, page_02.html page_03.html

=item B<--man>

Prints the manual page and exits.

=item B<--noresize>

Pictures are copied to the output directory only, and renmaed as appropriate, but are not reduced in size.

=item B<--nodraw>

Pictures do not have a copyright text drawn on them.

=item B<--nopics>

Don't actually include pictures.  Marginally useful for constructing pages with no pictures, just stories and so forth.  There are probably better tools for that than this :)

=item B<--outdir path> I<(default album)>

Specifies the output dir for the album tree.

=item B<--pichtmldir> I<(default pichtml)>

Specifies the subdirectory of the output dir (see --outdir) that the per picture html pages will be stored in.

=item B<--prefix fileprefix> I<(default web)>

This text is prepended to pictures in the output directory.  For example, given a list of pictures 3.JPG, 5.JPG, 6b.JPG, --prefix=mypics will result in the output files being named mypics_3.jpg mypics_5.jpg and mypics_6b.jpg.

Everything is always lower case in the output, and the separator is _.  If you don't like this, you know where to complain.

=item B<--quiet>

Opposite of --verbose

=item B<--reportfile file> I<(default tripreport.txt)>

Specifies a file to be included at the top of the first page.  (for instance a
trip report)  This file is inserted as raw text like so...

<div class="tripreport">reportfile is inserted here</div>

=item B<--resize resizeamount> I<(default 800x800>)>

Specifies that the source image files should be resized (reduced) when copied
to the output directory. Size parameter is in imagemagick form, and therefore
a string, so you can do what you will here if you wish.  Other values might be
"40%" for instance, see the imagemagick documentation for more info.  The
default is a string that will resize an image down, such that the longest
dimension is 800 pixels.  This preserves aspect ratio, and only resizes if
need be.

=item B<--rows num> I<(default 2)>

Number of rows per page to use when generating the index pages.

=item B<--stylesheet --style --css> I<(default /tweak2.css)>

Specify a complete relative link to a stylesheet you want, this is used for
both the per picture pages, and the thumbnail pages

=item B<--stylesheet2 --style2 --css2> I<(default /colour-tweak.css)>

Specify a complete relative link to a second stylesheet you want,
normally, you would use this for colours maybe?

=item B<--text_colour --text_color --colour --color colourname> I<(default orange)>

Specifies the colour used when drawing copyright text

=item B<--thumb_dir path> I<(default thumb)>

Specifies the subdirectory of the output dir (see --outdir) that generated thumbnails will be stored in.

=item B<--thumb_format format> I<(default jpg)>

Specifies the format that generated thumbnails will be

=item B<--thumb_prefix text> I<(default TN)>

As per --prefix, but for the thumbnails

=item B<--thumb_size resizeamount> I<(default 25%)>

As per --resize, but this time as a portion of the I<resized> pictures, not the originals.  ie, original pictures at 100%, resize at 40% and thumb_size at 25% will make thumbnails that are 10% of the originals.

This is a string for image magick, just as --resize is, if you are feeling adventurous :)

=item B<--title text> I<(default Title goes here)>

Specifies the title for the page.  This is a fairly important option :)

=item B<--verbose>

Prints out lots of status reporting

=back

=head1 SEE ALSO

perldoc PageGen
perldoc findtagged.pl

=head1 AUTHOR

Karl Palsson, E<lt>karl_AT_tweak.net.auE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Karl Palsson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 NOTES

[1] Nice according to Karl.

=cut
