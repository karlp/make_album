#!/usr/bin/env python3
"""
Scans a directory tree of "make_album" style albums,
and generates an index page.
Inspired by Karl's vintage perl scripts "kmkfrontpage.pl"


old way used to find all page1.html, keep full paths to webroot, sort by whatever,
then, walk the list, opening and closing UL/LI levels as the path levels changed!

That's... not horrible. but means it's very driven.  You're certainly not iterating like that

Eitherway, I need to load up all the sorting info up front.

Old raw date: -M time on page1.html files, no problem => Rgallery.mtime
alphabetical: easy, but not implemented, this was on relative path chunks,  Rgallery.page1.relative(app.where) ?
gallery based: not implemented yet, requires:
    => on page1, look for page* links,  (with checks to avoid other sorts of links...
    => get the last "picture" link, and then
        => read exif date out of html (that's what original did)
        ==> fallback to mtime of the file (for non-pic files being last for instance)
This is most reliable, but needs a bunch of html mechanizing...

Regardless, best method is using jinja loops recursively, follow their "sitemap" example!
Which requires not building a flat _list_ but building a heirarchy.
the sort options can still be used, you just build them differently.
so just add a "children" node to a gallery?

For starters, use alphabetical sort of path segments to make heirarchies, that tests the basics?
The -M time on page1 requires iterating quite a lot to create the heirarchy?

TODO - ... finish it?
"""
import argparse
import dataclasses
import datetime
import enum
import itertools
import logging
import operator
import os
import pathlib
import re
import typing
import unittest

import jinja2
from bs4 import BeautifulSoup

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


class AlbumSortOrder(enum.Enum):
    # mod time of gallery index
    MTIME_ASCENDING = enum.auto()
    MTIME_DESCENDING = enum.auto()
    # plain old alphabetical, no-one wants this..
    ALPHA_ASCENDING = enum.auto()
    ALPHA_DESCENDING = enum.auto()
    # exif date of last pic in gallery, default
    PIC_ASCENDING = enum.auto()
    PIC_DESCENDING = enum.auto()

def get_pic_date(fn):
    """
    Just use regexps.  We have old documents with no useful
    structure, so just look for the "Shooting Details" header, and then
    look for the Date Taken after that.
    returns a datetime object
    """
    #print("k, looking at pic page:", fn)
    with open(fn, "r") as fp:
        lines = fp.readlines()

    # skip ahead to "shooting details" line...
    found_d = False
    m = re.compile(r"date.*?: (.*\d)", re.IGNORECASE)
    for line in lines:
        if "details" in line.casefold():
            found_d = True
        if found_d:
            # Only look for date field after the details line.
            z = m.search(line)
            if z:
                dt = z.group(1)
                # now, it _might_ be an iso date, but it's probably not,
                # it's almost definitely using : instead of -
                try:
                    d = datetime.datetime.fromisoformat(dt)
                    return d
                except ValueError:
                    pass
                # ok, try and mangle it a bit...
                dt = dt.replace(":", "-", 2)
                try:
                    d = datetime.datetime.fromisoformat(dt)
                    return d
                except ValueError:
                    pass
                # Last try, maybe it just has a date?  (python is way less "complete"
                # Than perl's "str2time" which just understands everything...

                logging.warning("Couldn't find a parseable date in  date field?! %s -> %s", fn, dt)


def get_pic_date_blob_regexp(fn):
    """
    Just use regexps.  We have old documents with no useful
    structure, so just look for the "Shooting Details" header, and then
    look for the Date Taken after that.
    """
    with open(fn, "r") as fp:
        blob = fp.read()

    # insanely search for everything...
    m = re.compile(r"<h3>.*details.*date.*:(.*)", re.IGNORECASE)
    x = m.search(blob)
    #print(blob)
    if x:
        print("ok, found a match: ", x)
    if not x:
        print("Failed to find anythign in ", fn)
    #print("um, ok, ", x)



def get_pic_date_soup_incomplete(fn):
    """
    Given a full path to individual pic page, attempt to get the date from it.
    :param fn:
    :return: None if not reliably detected, or a unix timestamp otherwise.? (or a datetime instance?)
    """
    logging.debug("checking %s for a plausible image date", fn)
    with open(fn, "r") as fp:
        soup = BeautifulSoup(fp, "html.parser")

    hh = soup.find_all("h3")
    # Only one h3 with "Details" in the text.
    details = [h for h in hh if "Details" in h.contents[0]][0]
    print("contenst", [h.contents[0] for h in hh])
    print("detials: ", details)
    # now look at details.next... for the raw text...
    for x in details.next_elements:
        print("processing next ele", x)
        #if "Date" in x.contents:
        #    print("plausible date: ", x)



class RGallery:
    def __init__(self, page1, title=None, mtime=0):
        """
        Create a gallery from a plausible path.
        Probably should be a class method, so it can only return valid ones?
        """
        self.page1: pathlib.Path = page1
        self.href = self.page1.parent # without the page1.html bit, makes nicer urls...
        self.title: str = title
        self.mtime = mtime # This is just mod time of the page1 file!
        self.pictime = None
        self.create_date = datetime.datetime.fromtimestamp(mtime)

    def enrich(self, opts):
        """
        Enriches metadata, specifically, looks up the "pic date"
        by looking into the files of an album and finding the last picture and
        getting it's date to use.
        """
        fn = pathlib.Path(opts.where).joinpath(self.page1)
        with open(fn, "r") as fp:
            soup = BeautifulSoup(fp, "html.parser")
        # look for all links on the page...
        links = soup.find_all('a')
        page_links = [l for l in links if l.get("href").startswith("page_")]
        #print(f"Ok, found page links: {page_links}")
        if len(links) == 0:
            # Return, just use defaults
            return self

        # Start at the back page, last image, looking for a valid date.
        pic_date = None
        pages = reversed(page_links)
        while pic_date is None:
            page = next(pages, None)
            if page:
                xfile = self.page1.parent.joinpath(page.get("href"))
                logging.debug("Checking page: %s", xfile)
                with open(pathlib.Path(opts.where).joinpath(xfile), "rb") as fp:
                    soup = BeautifulSoup(fp, "html.parser")
            # otherwise, back to the page we're already on please!

            # now need picpage links, or at least agood way of determining them...
            # we want to get <a> that is inside <img>? can we do that easily?
            img_links = [i.parent.get("href") for i in soup.css.select("a > img")]
            for e in reversed(img_links):
                pic_date = get_pic_date(pathlib.Path(opts.where).joinpath(self.page1).parent.joinpath(e))
                if pic_date:
                    break
            if not page:
                # we tried every single followup page, and every single image on the front page
                break

        if pic_date:
            self.pictime = pic_date
            self.create_date = self.pictime
        else:
            logging.warning("No date found for album at all, falling back to default %s", self)
        return self

    def __repr__(self):
        return f"Gallery<p1={self.page1}, title={self.title}, create_date={self.create_date}>"


def get_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    ap.add_argument("--where", help="Where to scan (recursively) for scanfiles", default=".")
    ap.add_argument('--scanfile', help="Name of gallery 'page1' files", default="page_1.html")
    ap.add_argument('--template_index', help="Jinja template for index page", default="tweak.album-index.j2")
    ap.add_argument("--title", help="Page title", default="Karl's Photos of the World")
    ap.add_argument("--outfile", help="Output file name", default="index.html")
    # TODO probably needs more work on relative pathing?

    ap.add_argument('--rss_template', help="Jinja template for index page", default="feed.rss.j2")
    ap.add_argument("--rss_outfile", help="Output filename for RSS.xml", default="feed.rss")
    ap.add_argument("--rss_baseurl",
                    help="Base url where this page will live, used for generating correct URIs",
                    default="https://www.tweak.au/pics2")

    ap.add_argument("--force", action="store_true", help="Force re-generation of output file")
    ap.add_argument("--recent_days", type=int, help="Days to consider a gallery 'recent'", default=30)

    opts = ap.parse_args()

    return opts


def search_galleries(opts):
    p = pathlib.Path(opts.where)
    plausible = list(p.glob(f"**/{opts.scanfile}"))
    # need to strip off opts.where to generate our relative filenames...
    pages = [p.relative_to(opts.where) for p in plausible]
    logging.debug("Found plausible pages: %s", pages)

    galleries = []
    for p in list(plausible):
        logging.debug("processing plausible: %s", p)
        title = None
        mtime = p.stat().st_mtime

        dat = p.read_text("utf8")
        # old perl just did a regexp for <title>(.*?)</title> here....
        m = re.search("<title>(.*?)</title>", dat, flags=re.IGNORECASE)
        if m:
            title = m.group(1)
        if title is None:
            raise IndexError("No title found?!")
        logging.debug("Discovered title of %s", title)

        g = RGallery(p.relative_to(opts.where), title, mtime)
        galleries.append(g)

    return galleries

def organize2(opts, albums: typing.List[RGallery], sortorder: AlbumSortOrder):
    """
    Don't try and re-invent data structures, you failed at that first time on this...
    :param albums: list of album blobs, with easy metadata already collected.
    :param sortorder: a magic string right now
    :return: "sorted" input list..
    """
    if sortorder == AlbumSortOrder.ALPHA_ASCENDING:
        albums.sort(key=lambda x: x.page1)
        return albums
    if sortorder == AlbumSortOrder.ALPHA_DESCENDING:
        albums.sort(key=lambda x: x.page1, reverse=True)
        return albums

    if sortorder == AlbumSortOrder.MTIME_ASCENDING:
        albums.sort(key=lambda x: x.mtime)
        return albums
    if sortorder == AlbumSortOrder.MTIME_DESCENDING:
        albums.sort(key=lambda x: x.mtime, reverse=True)
        return albums

    if sortorder in [AlbumSortOrder.PIC_ASCENDING, AlbumSortOrder.PIC_DESCENDING]:
        [a.enrich(opts) for a in albums]
        albums.sort(key=lambda x: x.create_date, reverse=sortorder==AlbumSortOrder.PIC_DESCENDING)
        return albums

    # ok, need to go and do work to find the "last picture in a gallery"
    # yes, this is complicated and messy, but it's actually important, you just have to do it.

    # you need ~all of "getlastpicdate()" from the perl file.
    raise ValueError("Unimplemented yet boyo!")


def helper_inout(here: RGallery, prev: typing.Optional[RGallery], inwards):
    """
    Helper for template to calculate in/out heirarchies
    We're looking for divergent points in paths, and return lists of
    the right length to de-indent or indent with sub headings..
    """
    hp = here.href.parts[:-1]
    pp = []
    if prev:
        pp = prev.href.parts[:-1]
    if hp == pp:
        return []
    # ok, have to iterate over them to find divergent point
    x = itertools.zip_longest(hp, pp)
    for i, tup in enumerate(x):
        if tup[0] != tup[1]:
            # ok, we found a divergent point
            if inwards:
                return list(pp[i:])
            else:
                return list(hp[i:])
    return []


def helper_in(here: RGallery, prev: typing.Optional[RGallery]):
    return helper_inout(here, prev, True)


def helper_out(here: RGallery, prev: typing.Optional[RGallery]):
    return helper_inout(here, prev, False)


def do_main(opts):

    if os.path.exists(opts.outfile):
        if not opts.force:
            print(f"Output file: {opts.outfile} already exists, not trampling!")
            return

    galleries = search_galleries(opts)
    #print(" galls are ...", galleries)
    # ok, galleries is a flat list with metadata.  Now, to create a heirarchy based on our chosen sorting...
    #sortorder = AlbumSortOrder.MTIME_ASCENDING
    sortorder = AlbumSortOrder.PIC_DESCENDING
    hgalleries = organize2(opts, galleries, sortorder)


    # old version used a specific date length for "recent" based on generation date.
    cutoff = datetime.datetime.now() - datetime.timedelta(days=opts.recent_days)
    recent = [g for g in hgalleries if g.create_date > cutoff]

    # Apparently jinja doesn't like absolute paths?
    env = jinja2.Environment(loader=jinja2.FileSystemLoader([".", os.path.dirname(__file__), "/home/karlp/src/make_album"]),
                             autoescape=jinja2.select_autoescape(['html', 'xml']),
                             undefined=jinja2.DebugUndefined)
    env.globals = dict(opts=opts, title=opts.title, helper_in=helper_in, helper_out=helper_out)

    tpl = env.get_template(opts.template_index)
    with open(f"{opts.outfile}", "wb") as f:
        f.write(tpl.render(galleries=hgalleries, recent=recent).encode("utf8"))

    tpl = env.get_template(opts.rss_template)
    with open(f"{opts.rss_outfile}", "wb") as f:
        f.write(tpl.render(recent=recent,
                           base=opts.rss_baseurl,
                           now=datetime.datetime.now(),
                           ).encode("utf8"))


class TestHelpers(unittest.TestCase):

    def test_sibling_easy(self):
        a = RGallery(pathlib.Path("test-data/2022/August/sub-event/day1/page_1.html"))
        b = RGallery(pathlib.Path("test-data/2022/August/sub-event/day2/page_1.html"))
        z = helper_in(b, a)
        self.assertEqual([], z)
        q = helper_out(b, a)
        self.assertEqual([], q)

    def test_up1_easy(self):
        a = RGallery(pathlib.Path("test-data/2022/August/sub-event/day2/page_1.html"))
        b = RGallery(pathlib.Path("test-data/2022/August/main-event/page_1.html"))
        z = helper_in(b, a)
        self.assertEqual(["sub-event"], z)  # a length 1 array to bring in.
        q = helper_out(b, a)
        self.assertEqual([], q)

    def test_up3_out2_easy(self):
        a = RGallery(pathlib.Path("test-data/2022/August/sub-event/day2/page_1.html"))
        b = RGallery(pathlib.Path("test-data/2021/May/wild-event/page_1.html"))
        z = helper_in(b, a)
        self.assertEqual(["2022", "August", "sub-event"], z)  # a length 3 array to bring in.
        q = helper_out(b, a)
        self.assertEqual(["2021", "May"], q)

    def test_out_start(self):
        a = RGallery(pathlib.Path("test-data/2022/August/sub-event/day2/page_1.html"))
        z = helper_in(a, None)
        self.assertEqual([], z)  # no closing
        q = helper_out(a, None)
        self.assertEqual(["test-data", "2022", "August", "sub-event"], q)

    def test_parallel_fail(self):
        a = RGallery(pathlib.Path("test-data/2022/March/miscstream/page_1.html"))
        b = RGallery(pathlib.Path("test-data/2021/March/otherthing/page_1.html"))
        z = helper_in(b, a)
        self.assertEqual(["2022", "March"], z)
        q = helper_out(b, a)
        self.assertEqual(["2021", "March"], q)


if __name__ == "__main__":
    myopts = get_args()
    do_main(myopts)
