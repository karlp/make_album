#!/usr/bin/perl -w
# COPYRIGHT Karl Palsson, 2002, 2003, 2004, 2005, 2012
# This scans and creates the index at tweak.net.au/pics2

use strict;

use Getopt::Long;
use Pod::Usage;
use File::Find;
use File::Basename;
use File::stat;
use POSIX qw(strftime);
use Carp;
use XML::RSS;
use Date::Parse;
use HTML::TreeBuilder;

# App defaults
my $outfile = "index.shtml";
my $scanfile = "page_1.html";
my $where = ".";
my $htmlbase = ".";
my $page_title = "Karl's Photos of the World";
my $page_desc = "Daily life, travel, work and play, some pictures, some photos";

my $timefornew = 30;
my $newtag = '<span class="newgallery">NEW</span>';

my $rss = 1; # enable rss 2.0 output for "new" galleries
my $rss_file = "feed.rss";
my $rss_title = $page_title;
my $rss_baseurl = "http://www.tweak.net.au/pics2";
my $rss_description = "$page_desc - galleries that have been updated in the last
$timefornew days (since feed publication date)";

my $sortby = "el";
my $non_pic_pattern = "avi|gif|mov|mp4|flv|ogv|mkv";  # move up to config when this works....


my $help;
my $man;
my $verbose;
my $debug;

# Internal
my @indexfiles;  #raw files
my @relfiles;  #relative links to page files

# protos
sub listsort($);

GetOptions(
    'outfile=s' => \$outfile,
    'scanfile=s' => \$scanfile,
    'where=s' => \$where,
    'man' => \$man,
    'newtime=i' => \$timefornew,
    'help' => \$help,
    'verbose' => \$verbose,
    'debug' => \$debug,
    'htmlbase=s' => \$htmlbase,
    'page_title=s' => \$page_title,
    'sort=s' => \$sortby,
    ) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# find list of files then.
find(\&wanted, $where);

listsort($sortby);

croak "No index pages found, aborting" if ((scalar @indexfiles) == 0);

print "Order list follows\n" if $verbose;
foreach my $file (@indexfiles) {
    print "File (ordered) = $file\n" if $verbose;
    # strip off the leading path details.
    # (So we can have relative paths for nice html :)
    my ($leadin, $relpath) = split m!$htmlbase!, $file,2;
    $relpath =~ s!/!!; # replace first slash only!
    push @relfiles, $relpath;
}

# Note, that we just pray that I've maintained the order of both lists in
# sync.  Should really be done in "something better" :)

open (FH, ">$outfile") or croak "Can't open $outfile: $!\n";
select FH;
print <<"HEADER";
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<link rel="alternate" href="feed.rss" type="application/rss+xml" title="RSS feed for this page">
<title>$page_title</title>

<script src="jquery-1.4.2.min.js" type="text/javascript"></script>
<script>
\$(document).ready(function(){
    // Your code here
    \$(".createdate").each(function (i) {
        d = new Date(\$(this).text());
        now = new Date();
        daysAgo = Math.floor((now - d) / (1000 * 60 * 60 * 24));
        if (daysAgo == 0) {
            \$(this).text("today");
        } else {
            \$(this).text(daysAgo + " days ago");
        } 
    });
 });
</script>
<link rel="StyleSheet" href="/tweak.css" type="text/css">
</head>
<body>
<div class="navigation"><a href="/">Home</a></div>
<div class="main">
<!--#include virtual="/include/lastupdated.shtml"-->
<h2>$page_title</h2>
<p>$page_desc
<p>Pages marked $newtag have been added (or just updated) within $timefornew days of this page being created
<hr>
HEADER

my $index = 0;
my $curr_depth = 0;
my $curr_name = "";
my $prev_file = "";

my %newgals;
my %newtimes;
my $bodytext = "";
my $today = time();
foreach my $file (@relfiles) {
    my $thisfile = $indexfiles[$index++];
    open HF, "<$thisfile" or croak "Couldn't open $file: $!";
    print STDOUT "Processing $thisfile for inclusion\n" if $verbose;

    # Grab the page title, and use that as the entry description
    my $page_desc;
    while (<HF>) {
        m!<title>(.*?)</title>!i;
        $page_desc = $1;
    }
    close HF;
    $page_desc = "No description in file" unless $page_desc;
    #$page_desc =~ s/&/&amp;/g; # let it go, fixed in page gen, so it should be sanitized by here

    #### Now print the page
    

    my @elems = split m!/!, $file;
    my @prev_elems = split m!/!, $prev_file;
    
    # -2 because the activity gets it's own month, and the file is a final level
    my $num_elems = @elems - 2;
    my $num_prev_elems = @prev_elems - 2;

    # this is the number of shared directory elements that we should look at.
    # we only do this so we dont' compare /ab/cd/ef/gh with /ab/xyz and get index bounds
    # issues. :)
    my $min_elems = ($num_elems < $num_prev_elems ? $num_elems : $num_prev_elems);
     
    my $i = 0;
    while ($i < $min_elems) {
    	if ($elems[$i] ne $prev_elems[$i]) {
    	    last;
    	}
    	$i++;
    };
    
    # $i now has the point at which the two branches diverge, if at all.
    # so if $i < $curr_depth, then we need to go back out to level $i, and 
    # back into the level needed for this file, creating dirs as we go.
    # if $i == curr_depth, (which it can, but it can never be greater, 
    # min_elems is always curr_depth or less)  then we are in at least 
    # the same branch to here, but we may need to go out further!
    # ie, into the actual month listing
    
    # hence, we care about how far apart $i and the current depth are, 
    my $diff = $curr_depth - $i;
    
    if ($i == $curr_depth) {
   	    if ($i < $num_elems) {
            while ($i < $num_elems) {
                $bodytext .= "<li>$elems[$i]<ul>\n";
                $i++;
            }
    	        
        } else {
            # this is the normal case, we do nothing here. staying on the same depth
            # and no differences beneath that depth
        }
    } else {
        # $i is not the current depth, so we need to go back in.  ($i can 
        # never be greater than the current depth, because we stop at min_elems
        # we need to go back from $curr_depth to $i.
        $bodytext .= "</ul>\n" x ($curr_depth - $i);
        # now we need to go from $i out to the new depth, creating as we go...
        while ($i < $num_elems) {
            $bodytext .= "<li>$elems[$i]<ul>\n";
            $i++;
        }
    }

    print STDOUT "Curr depth = $curr_depth, this depth = $num_elems\n" if $verbose;
    
    $curr_depth = $num_elems;
    $bodytext .= "<li><a href=\"$file\">$page_desc</a> ";

    my $thisTime = stat($thisfile)->mtime;
    my $SECS_PER_DAY = 60 * 60 * 24;
    if ($thisTime > ($today - ($timefornew * $SECS_PER_DAY))) {
        $bodytext .= $newtag;
        $newgals{$file} = $page_desc;
        $newtimes{$file} = $thisTime;
    }
        
    $bodytext .= "</li>\n";
    
    $prev_file = $file;
}

print "<h3>Recent Galleries";
# add one of those orange "get this feed" blogtastic buttons
print " <a href='$rss_file'><img src='feed-icon-14x14.png' alt='rss feed icon' width='14'
height='14'></a>" if $rss;
print "</h3>\n<ul>\n";

# make the rss stub, we'll then add in all the "recent" galleries and write it out
# be nice to only make this if rss is on, and all that sort of lovely autoloading
# plumbing, but I'm not as l33t as some.
my $rsso = new XML::RSS (version => "2.0") if $rss;
$rsso->channel(title => $rss_title,
    link => $rss_baseurl,
    description => $rss_description,
    pubDate => scalar(gmtime)) if $rss;

my @gallist = sort {$newtimes{$b} <=> $newtimes{$a}} keys %newtimes;
foreach my $recent (@gallist) {
    print "<li><a href=\"$recent\">$newgals{$recent}</a>";
    # hack and use the same key for both hashs
    # (not hacky enough to work out how to reorder by the values!)
    my $human = strftime("%Y %b %e", localtime($newtimes{$recent}));
    printf " gallery created <span class='createdate'>%s</span></li>\n", $human;

    # and now, update the rss!
    $rsso->add_item(title => $newgals{$recent},
        permaLink => "$rss_baseurl/$recent" . "?src=rss",
        link => "$rss_baseurl/$recent" . "?src=rss",
        description => "you'll have to go to the gallery....") if $rss
}
$rsso->save($rss_file) if $rss;


print "</ul><hr>\n";
print "<ul>\n";
print $bodytext;

print "</ul>"; # final month
print "</ul>"; # final year
print "</ul>"; # end gallery
print "\n<p><a href=\"/pics\">Older galleries</a>";

print "\n</div>";
print "</body></html>";
close FH;

sub wanted () {
    return unless ($_ eq $scanfile);
    printf "Found an index page: %s\n", $File::Find::name if $verbose;
    push @indexfiles, $File::Find::name;
}

# List sorting is no longer trivial.
# we have all sorts of options, and some of them are not trivial
sub listsort ($) {
    my $sortby = shift;

    if ($sortby eq "gf") {
	@indexfiles = sort { -M $a <=> -M $b } @indexfiles;
	return;
    } 
    if ($sortby eq "gl") {
	@indexfiles = sort { -M $b <=> -M $a } @indexfiles;
	return;
    } 
    if ($sortby eq "aa") {
	@indexfiles = sort @indexfiles;
	return;
    } 
    if ($sortby eq "ad") {
	@indexfiles = reverse sort @indexfiles;
	return;
    }
    if ($sortby eq "ef") {
	@indexfiles = sort {
	    getlastpicdate($a) <=> getlastpicdate($b) 
	} @indexfiles;
	return;
    }
    if ($sortby eq "el") {
	@indexfiles = sort {
	    getlastpicdate($b) <=> getlastpicdate($a) 
	} @indexfiles;
	return;
    }

    carp "Unknown sort order, leaving unsorted!";

}


# load a tree from a file, and use utf8 please!
# because ...->new_from_file doesn't let me set utf8 mode.
sub tree_from_file {
    my $filename = shift;
    my $tree = HTML::TreeBuilder->new();
    $tree->utf8_mode(1);
    $tree->parse_file($filename);
    return $tree;
}

# for a given gallery front page (page_1.html type), come up with a date
# (in seconds since the epoch) that represents when the event represented by
# the gallery took place.  This gives us another metric.  (besides the creation
# time of the gallery itself)
# We look for, in order,
# 1. exif date of the final picture of the gallery
# 2. last mod date of the picture itself
# 3. last mod date of the gallery page if no pictures

my %picdates; #caching please!

sub getlastpicdate {
    my $frontpage = shift;
    my $date;
    return $picdates{$frontpage} if defined $picdates{$frontpage};

    print STDOUT "Calculating date for frontpage: $frontpage" if $verbose;

    my ($junk1, $pathbase, $junk2) = fileparse($frontpage);

    # Look for page* links to see if this is the only page, or if we should
    # go to a later page
    my $tree = tree_from_file($frontpage);
    my @links_raw = map {$_->attr('href')} $tree->look_down("_tag", "a");
    # remove empty links, like for keyboard shortcut stuff
    my @links = grep ($_, @links_raw);

    # so, we could have links to other pages, links to pictures, or links 
    # from the story to external sites.
    my $numlinks = scalar(@links);

    # no links at all, so return the mod time of the gallery
    if ($numlinks == 0) {
        $date = stat($frontpage)->mtime;
        print "no_pics: $date\n" if $verbose; #run on print
        $picdates{$frontpage} = $date;
        return $date;
    }

    # look for page* links, but make sure we don't include external links
    # that just happen to have page in them
    my @pagelinks = grep (!/http/, @links); 
    @pagelinks = grep (/page/, @pagelinks);
    if (scalar(@pagelinks) > 0) {
	my $newfile = pop @pagelinks;
	$newfile = $pathbase . $newfile;
        $tree = tree_from_file($newfile);
    }
    @links = map {$_->attr('href')} $tree->look_down("_tag", "a");
    # secondary pages don't contain story, so only links are to pictures
    # A little gross, but after some js hacking, we don't have clear prefixes on the per pic html files
    @links = grep (!/page_.*.htm/, @links);
    @links = grep (/.html?$/, @links);
    my $picpage = pop @links;
    # FIXME - if there are no picpages, this will bomb....
    # finally, we have the picture html page, to read the date from.  
    # (I'm reading the date from the exif in the html, not the exif in the file)
    my $picfile = $pathbase . $picpage;

    $tree = tree_from_file($picfile);

    # XXX - more hardcoded strings! from PageGen.pm
    $tree->as_HTML() =~ /Date.*?:(.*)<br/;
    $date = $1;

    # no exif data
    # so we need to get the actual picture itself, and look at it's last
    # mod time.
    if ($date =~ /Bad/ || $picfile =~ /$non_pic_pattern/) {
        print " falling back to path based date:" if $verbose;
        my @piclist = map {$_->attr('src')} $tree->look_down("_tag", "img");
        my $relpicfile = basename($piclist[0]);
        my $realpicture = $pathbase . $relpicfile;
        my @dateparts = split(/\//, $pathbase);
        $date = str2time("3 $dateparts[2] $dateparts[1]"); 
        if (defined $date) {
            print " $date\n" if $verbose;
        } else {
            print "No date from path, falling back to NOW!\n" if $verbose;
            $date = time();
        }
    } else {
	# modify the date to replace the first two : with -
	$date =~ s/:/-/;
	$date =~ s/:/-/;
	$date = str2time($date);
	print " exif: $date\n" if $verbose; #run on sentence from earlier
    }
    $picdates{$frontpage} = $date;
    return ($date);
}    


__END__

=head1 NAME

kmkfrontpage.pl - Generates an index page linking to all make_album outputs

=head1 SYNOPSIS

  kmkfrontpage.pl
  kmkfrontpage.pl --outfile myindex.html --where=/web/myalbums
  kmkfrontpage.pl --scanfile=my_page_1.html

=head1 ABSTRACT

stuff

=head1 OPTIONS

=over 8

=item B<--outfile> I<(default index.shtml)>

Name of output file

=item B<--scanfile> I<(default page_1.html)>

Name of file to be looking for in the directory heirarchy to make links to.

=item B<--where> I<(default .)>

Where to start looking for those files

=item B<--newtime> I<(default 10)>

Galleries that have a frontpage file mod within the last X many days will be 
flagged with <span class="newgallery">NEW</span>

=item B<--htmlbase> I<(default .)>

What the base will be, this goes with where to work out how to make relative links from the found the files.

=item B<--page_title> I<(default Karl's digital pics)>

Title of the front page generated.

=item B<--sort string> I<(default el)>

Order to sort lists by.

aa  Alphabetical, ascending (a-z)

ad  Alphabetical, descending (z-a)

ef  Event based (date from picture exif), most recent first

el  Event based (date from picture exif), most recent last

gf  Gallery based (date from gallery creation), most recent first

gl  Gallery based (date from gallery creation), most recent last

Default of ef makes pages with newest material at the top.

=back

=head1 AUTHOR

Karl Palsson, E<lt>karl_AT_tweak.net.auE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Karl Palsson

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 NOTES

none

=head1 BUGS

running this on remote dirs is sketchy at best
(I always run it in the directory I want the file to be in)

=cut
