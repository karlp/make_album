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

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)


@dataclasses.dataclass
class TGallery:
    title: str
    page1: str
    year: int
    month: int
    month_name: str

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
        #self.month = 1
        #self.year = 1999 # should we get from the path instead?
        #self.month_name = "lol"
        #self.path_elems = page1.parts[:-1]
        #self.children = []

    def __repr__(self):
        return f"Gallery<p1={self.page1}, title={self.title}, mtime={self.mtime}>"



def get_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    ap.add_argument("--where", help="Where to scan (recursively) for scanfiles", default=".")
    ap.add_argument('--scanfile', help="Name of gallery 'page1' files", default="page_1.html")
    ap.add_argument('--template_index', help="Jinja template for index page", default="tweak.album-index.j2")
    ap.add_argument("--title", help="Page title", default="Karl's Photos of the World")
    ap.add_argument("--outfile", help="Output file name", default="index.html")
    # TODO probably needs more work on relative pathing?

    ap.add_argument("--rss_outfile", help="Output filename for RSS.xml", default="feed.rss")
    ap.add_argument("--rss_baseurl",
                    help="Base url where this page will live, used for generating correct URIs",
                    default="https://www.tweak.au/pics2")

    ap.add_argument("--force", action="store_true", help="Force re-generation of output file")

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

def organize2(albums: typing.List[RGallery], sortorder: AlbumSortOrder):
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

    if sortorder not in [AlbumSortOrder.PIC_ASCENDING, AlbumSortOrder.PIC_DESCENDING]:
        raise ValueError("Unsupported sort order", sortorder)

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
    print(" galls are ...", galleries)
    # ok, galleries is a flat list with metadata.  Now, to create a heirarchy based on our chosen sorting...
    #sortorder = AlbumSortOrder.MTIME_ASCENDING
    sortorder = AlbumSortOrder.ALPHA_ASCENDING
    hgalleries = organize2(galleries, sortorder)


    recent = [] # need to pick this off.... when? it's the same list? or does organize return this?



    # Apparently jinja doesn't like absolute paths?
    env = jinja2.Environment(loader=jinja2.FileSystemLoader([".", os.path.dirname(__file__), "/home/karlp/src/make_album"]),
                             autoescape=jinja2.select_autoescape(['html', 'xml']),
                             undefined=jinja2.DebugUndefined)
    env.globals = dict(opts=opts, title=opts.title, helper_in=helper_in, helper_out=helper_out)

    tpl = env.get_template(opts.template_index)

    with open(f"{opts.outfile}", "wb") as f:
        f.write(tpl.render(galleries=hgalleries, recent=recent).encode("utf8"))


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
