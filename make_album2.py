#!/home/karlp/src/make_album/.env3/bin/python
#!/usr/bin/env python3
"""
Turns a list of files (pictures, movies...) into a static html gallery.
Inspired by Karl's vintage perl scripts, "make_album.pl" and "PageGen.pm"
but updated to be a bit more maintainable going forward.

TODO:
 * sorting options on command line (ie, --reverse is used for misc galleries!)
 * support for file lists (ie, used by misc galleries)

"""
import argparse
import configparser
import datetime
import glob
import itertools
import logging
import math
import os
import subprocess

import jinja2
from PIL import Image, ImageFont, ImageDraw
import exiftool # The only thing we trust.
import pyproj

logging.basicConfig(level=logging.DEBUG)
log = logging.getLogger(__name__)
logging.getLogger("PIL").setLevel(logging.INFO)

class Item:
    """Represents an item that gets an individual page"""
    def __init__(self, srcfn, opts, exiftool):
        """
        Create a new item to publish
        :param srcfn: the _source_ filename, normally just a relative path, eg "photo1234.jpg"
        :param opts: app opts, used for lots of settings.
        """
        self.opts = opts # save for later... (lazy sneaky globals are awesome...)
        self.srcfn = srcfn
        self.bn = os.path.basename(self.srcfn)
        self.base = os.path.splitext(self.bn)[0]
        # these are real files (but not all are created)
        self.ofn = f"{opts.outdir}/{opts.item_prefix}{self.base}{opts.item_suffix}.{opts.image_format}"
        self.ofn_base = f"{opts.outdir}/{opts.item_prefix}{self.base}{opts.item_suffix}"
        self.ofn_mp4 = f"{self.ofn_base}.mp4"
        self.ofn_ogv = f"{self.ofn_base}.ogv"
        self.ofn_webm = f"{self.ofn_base}.webm"
        self.tfn = f"{opts.outdir}/{opts.thumb_prefix}{self.base}{opts.thumb_suffix}.{opts.thumb_format}"
        self.page_fn = f"{opts.outdir}/{opts.picpage_prefix}{self.base}.html"

        # Load any available metadata from the file itself.
        # pyexiftool 0.5+ returns a list, even if we only asked for one file.
        self.metadata = exiftool.get_metadata(self.srcfn)[0]
        # Also, look for any metadata in sidecar files...
        self.meta_title = None
        description_fn = f"{os.path.dirname(os.path.abspath(self.srcfn))}/descript.ion"
        if os.path.exists(description_fn):
            with open(description_fn, "rb") as f:
                entries = [l.decode("iso-8859-1") for l in f.readlines()]
                for e in entries:
                    fn, descr = e.split(maxsplit=1)
                    if fn == self.bn:
                        self.meta_title = descr


        self.title_share = self.title # facebook opengraph thingy

        # The html page that "presents" this item
        self.page_from_index = os.path.relpath(self.page_fn, opts.outdir)
        self.page_from_page = os.path.relpath(self.page_fn, os.path.dirname(self.page_fn))  # ~ to itself as all pages are in same location

        self.dl_mp4 = os.path.relpath(self.ofn_mp4, os.path.dirname(self.page_fn))
        self.dl_ogv = os.path.relpath(self.ofn_ogv, os.path.dirname(self.page_fn))
        self.dl_webm = os.path.relpath(self.ofn_webm, os.path.dirname(self.page_fn))

        # XXX make sure you only pass a _directory_ as arg 2!
        # used to make sure that images can be in separate directories...
        self.ofn_from_page = os.path.relpath(self.ofn, os.path.dirname(self.page_fn))
        # thumbs are referenced from the main page...
        self.tfn_from_index = os.path.relpath(self.tfn, opts.outdir)
        self.tfn_from_page = os.path.relpath(self.tfn, os.path.dirname(self.page_fn))

        # used to contain relative hrefs for navigation
        self.prev = None
        self.next = None

    def is_video(self):
        for ext in [".mp4", ".ogv", ".mov", ".webm", ".mkv"]:
            if ext in self.srcfn:
                return True
        return False

    def is_pano(self):
        return "pano" in self.bn
    def is_stack(self):
        return "stack" in self.bn
    def is_art(self):
        return "art" in self.bn

    def is_photo(self):
        return not self.is_video() and not self.is_pano()

    def get_lens(self) -> str:
        el = self.metadata.get("EXIF:LensModel")
        if el:
            return el
        # Otherwise, might be zoom, with max/min, might be fixed, might be a phone...
        # we would _like_ the print converted Composite:Lens, but we can't get that back again...
        # so we have to do it ourselves!? how fucking gross is this...
        # priority list of tags to pull from...
        mmin = self.metadata.get("MakerNotes:MinFocalLength")
        mmax = self.metadata.get("MakerNotes:MaxFocalLength")
        if mmin and mmax:
            if mmin == mmax:
                return "Fixed"
            return f"{mmin}mm - {mmax}mm Zoom"

        return self.metadata.get("Composite:Lens",
                                 "Unknown")

    def get_shutter_speed(self) -> str:
        # We _normally_ want the machine non-cnverted times, except when we don't
        # as far as I can tell, we can't have the same tag bothconverted and not-converted in the same instance.
        # boooo
        shutter_raw = float(self.metadata.get("Composite:ShutterSpeed", -1))
        if shutter_raw > 0:
            if shutter_raw < 0.5:
                val = 1/shutter_raw
                return f"1/{val:.0f} sec"
            else:
                return f"{shutter_raw} sec"
        #return self.metadata.get("Composite:ShutterSpeed")

    def title(self):
        title = self.bn
        if self.is_video():
            # OGV and MKV containers can have metadata, or the sidecar title.
            title = self.metadata.get("Title", self.meta_title)
        else:
            # Most important at the bottom...
            title = self.metadata.get("EXIF:UserComment", title)
            title = self.metadata.get("IPTC:Caption-Abstract", title)
            title = self.metadata.get("XMP:Title", title)
        return title


    def importance(self):
        imp = 0
        if self.is_video():
            # We don't have rankings for any decent metadata for video,
            # so count it as important if it has a caption of any sort
            if self.title():
                return self.opts.filter_imp
        else:
            # Legacy binary flagging, used on some old images.
            if self.metadata.get("IPTC:SpecialInstructions", "") == "Publish":
                imp = 3
            # Most important at the bottom...
            imp = self.metadata.get("IPTC:Urgency", imp)
            imp = self.metadata.get("XMP:Urgency", imp)
            imp = self.metadata.get("XMP:Rating", imp)
            return int(imp)
        return 0

    def is_included(self):
        if self.importance() >= self.opts.filter_imp:
            return True
        if "Publish" in self.metadata.get("SpecialInstructions", ""):
            return True

    def copyright(self):
        con = self.metadata.get("MakerNotes:OwnerName", self.opts.copyright)
        # A little lame having to string parse backwards, but exiftool's not a great api in snek land.
        dd = datetime.datetime.strptime(self.meta_create_date(), "%Y:%m:%d %H:%M:%S")
        return f"{con}, {dd.year}"

    def meta_create_date(self):
        """
        Get a "creation date" from a file's metadata, regardless of what of file it is...
        TODO - use actual datetimeobjects natively, not strings?
        :return:
        """
        # higher priority last.
        d = datetime.datetime.fromtimestamp(os.path.getmtime(self.srcfn))
        d = datetime.datetime.strftime(d, "%Y:%m:%d %H:%M:%S")
        d = self.metadata.get("QuickTime:CreateDate", d)
        d = self.metadata.get("EXIF:DateTimeOriginal", d)
        return d

    def geo_iceland(self):
        """
        Returns a tuple in coordinates suitable for iceland map services, if the item
        both _has_ geo data, and it's in iceland. otherwise, None
        """
        dy = self.metadata.get("Composite:GPSLongitude", None)
        dx = self.metadata.get("Composite:GPSLatitude", None)
        if dx and dy:
            if dy > -30.87 and dy < -5.55 and dx > 59.96 and dx < 69.59:
                t = pyproj.Transformer.from_crs("EPSG:4326", "EPSG:3057")
                ox, oy = t.transform(dx, dy)
                return ox, oy
        return None

    def mk_thumb(self):
        """
        create a thumbnail of the resource
        Expects output conversion to already be complete, as this means we can operate on final files. (for faster processing)
        :return:
        """
        if os.path.exists(self.tfn) and not self.opts.force:
            print(f"skipping thumb creation for {self.tfn}: already exists")
            return
        log.debug("Creating thumb for %s", self.bn)
        if self.is_video():
            # Make a thumbnail, then overlay a "video" type icon on it....
            subprocess.run(f"ffmpegthumbnailer -i {self.ofn_mp4} -s {self.opts.thumb_dimension} -o {self.tfn}".split(), check=True)
            with Image.open(self.opts.thumb_overlay_video) as overlay:
                ox, oy = overlay.size
                with Image.open(self.tfn) as thumb:
                    tx, ty = thumb.size
                    thumb.paste(overlay, (tx//2-ox//2, ty//2-oy//2), overlay)
                    thumb.save(self.tfn)
        else:
            with Image.open(self.srcfn) as im:
                im.thumbnail((self.opts.thumb_dimension, self.opts.thumb_dimension))
                os.makedirs(os.path.dirname(self.tfn), exist_ok=True)
                self.thumb_x, self.thumb_y = im.size
                im.save(self.tfn)

    def mk_output(self):
        """
        Creates the "final" output file.

        Expects all metadata to already be attached to the item.
        :return:
        """
        if os.path.exists(self.ofn) and not self.opts.force:
            print(f"skipping output creation for {self.ofn}: already exists")
            return
        log.debug("Creating output for %s", self.bn)
        if self.is_video():
            cmd = f"make_web_videos.sh -i {self.srcfn} -o {self.ofn_base} -m -w"
            subprocess.run(cmd.split(), check=True, shell=False)
        else:
            with Image.open(self.srcfn) as im:
                if (self.is_pano()):
                    # We only want to constrain height on panos, not longest side.
                    old_w, old_h = im.size
                    new_height = self.opts.image_dimension
                    new_width  = new_height * old_w / old_h
                    im.thumbnail((new_width, new_height))
                else:
                    im.thumbnail((self.opts.image_dimension, self.opts.image_dimension))
                self.image_x, self.image_y = im.size

                # All of this could be "config"  (not gallery metadata, but "user config" sort of thing.
                # Can't have options for _alllll_ of it, surely?
                fnt = ImageFont.truetype("DejaVuSans", 15)
                d = ImageDraw.Draw(im)
                d.text((self.image_x-10, self.image_y-10), self.copyright(), font=fnt, fill="orange", anchor="rd")

                os.makedirs(os.path.dirname(self.ofn), exist_ok=True)
                im.save(self.ofn)


    def __repr__(self):
        s = f"""Item<srcfn={self.srcfn}, title="{self.title()}", ofn={self.ofn}, """

        if self.prev:
            s += f", prev={self.prev.srcfn}"
        if self.next:
            s += f", next={self.next.srcfn}"
        s += ">"
        return s

class Page:
    """Represents a thumbnail index page"""
    def __init__(self, idx, opts):
        self.idx = idx
        self.opts = opts

def update_metadata(opts):
    """
    Given the original options blob, enrich it based on the gallery_metadata.
    remember that specified command line options should take precedence over metadata files
    :param opts:
    :return:
    """
    # Our "metadata" files are ini style, but with no sections, so no section header.
    # fake it til it makes it....
    blob = opts.gallery_metadata.read().decode("utf8")
    md_s = f"[general]\n{blob}"
    config = configparser.ConfigParser()
    config.read_string(md_s)

    cfg = config["general"]
    if not opts.title:
        opts.title = cfg.get("title", opts.title_default)
    if not opts.outdir:
        opts.outdir = cfg.get("outdir", opts.outdir_default)
    if not opts.iptc_utf8:
        z = cfg.get("iptc_utf8")
        if z and z.lower()[0] in ["y", "t", "1"]:
            opts.iptc_utf8 = True
    return opts

def searchable_file(string):
    """Look for a file in pwd, and also the location of this script itself"""
    if os.path.exists(string):
        return string
    fn = os.path.join(os.path.dirname(__file__), string)
    if os.path.exists(fn):
        return fn
    # Gross hack to look in repo as well.
    fn = os.path.join("/home/karlp/src/make_album", string)
    if os.path.exists(fn):
        return fn
    raise argparse.ArgumentTypeError(f"File not found: {string}")

def get_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    ap.add_argument('infiles', metavar="file", nargs="+", help="List of input files to include/process")
    # FIXME - these need to default to not set, and allow overrides too...
    ap.add_argument('--tripreport', type=argparse.FileType('rb', 0), help="preformatted html tripreport/description", default="tripreport.txt")
    ap.add_argument('--gallery_metadata', type=argparse.FileType('rb', 0), help="ini style metadata file", default="gallery.metadata")
    #ap.add_argument('--template_index', type=argparse.FileType('rb', 0), help="Jinja template for thumbnail index pages", default="tweak.index.j2")
    ap.add_argument('--template_index', help="Jinja template for thumbnail index pages", default="tweak.index.j2")
    #ap.add_argument('--template_picpage', type=argparse.FileType('rb', 0), help="Jinja template for individual picture pages", default="tweak.picpage.j2")
    ap.add_argument('--template_picpage', help="Jinja template for individual picture pages", default="tweak.picpage.j2")
    ap.add_argument("--rows", type=int, default=2, help="rows per page")
    ap.add_argument("--cols", type=int, default=3, help="columns per page")

    ap.add_argument("--copyright", default="Karl Palsson", help="What name to use as copyright, if _not_ found in the files themselves.")

    ap.add_argument("--title", help="Gallery title, supersedes gallery metadata")
    ap.add_argument("--title_default", help="Gallery title fallback", default="My Generated Gallery")
    ap.add_argument("--outdir", help="Output directory, supersedes gallery metadata")
    ap.add_argument("--outdir_default", help="Output directory fallback", default="my-gallery.generated")
    ap.add_argument("--filter_imp", type=int, default=2, help="Filter out items with 'importance' less than this value.")

    ap.add_argument("--iptc_utf8", default=False, action="store_true",
                    help="If your IPTC captions are (incorrectly) in utf8, instead of latin1, this can help convert them on load, assumed to be fixed for entire gallery")

    ap.add_argument("--image_dimension", default=1200, help="Maximum dimension of resized output images")
    ap.add_argument("--image_format", default="jpg", choices=["jpg"], help="format of resized output images (for static images only)")
    ap.add_argument("--item_prefix", default="", help="filename prefix for resized output files")
    ap.add_argument("--item_suffix", default="_web", help="filename suffix for resized output files")

    ap.add_argument("--picpage_prefix", default="disp_", help="filename prefix for per picture html")

    ap.add_argument("--thumb_format", default="png", choices=["png", "jpg"], help="what format should thumbs be created in")
    ap.add_argument("--thumb_prefix", default="thumbs/", help="filename prefix for thumbnails")
    ap.add_argument("--thumb_suffix", default="_TN", help="filename suffix for thumbnails")
    ap.add_argument("--thumb_dimension", default=250, help="Maximum dimension of a thumbnail image, in pixels")
    ap.add_argument("--thumb_overlay_video", default="overlayPlayIcon.png", help="a file to overlay on a video thumbnail", type=searchable_file)

    ap.add_argument("--force", action="store_true", help="Force re-conversion of output images/files.")

    opts = ap.parse_args()
    opts = update_metadata(opts)

    return opts

def handle_sorting(items, opts):

    def _by_file_name(i):
        return os.path.basename(i.srcfn)

    def _by_file_date(i):
        return os.path.getmtime(i.srcfn)

    def _by_metadata_date(i):
        return i.meta_create_date()

    items.sort(key=_by_file_name)
    #items.sort(key=_by_metadata_date)
    #items.sort(key=_by_file_date)

    return items

def do_main(opts):
    # iterate files.... and load metadata for them...
    # if we're inside pycharm or some other environments, we might not have had shell expansion... boo..
    # if we have had shell expansion, globbing again does no harm.
    globbed_inputs = [glob.glob(f) for f in opts.infiles]

    # TODO - it might be nice to have exiftool read everything, then just work from that,
    # instead of running it on each file one by one?
    # In the meantime, we use check_execute=False as we are often passing "*" as the file list
    # and we don't care about failures on files that don't have all fields!
    cargs = ["-G", "-n"] # Plain exiftool defaults
    if opts.iptc_utf8:
        cargs.extend("-charset iptc=utf8".split())
    with exiftool.ExifToolHelper(common_args=cargs, check_execute=False) as et:
        items = [Item(f, opts, et) for f in set().union(*globbed_inputs)]

    items = handle_sorting(items, opts)
    if opts.filter_imp:
        items = [i for i in items if i.is_included() ]

    log.info("Processing %d items for the gallery", len(items))
    for n,item in enumerate(items):
        # add links, ala linked list, but... not as fancy..
        if n > 0:
            item.prev = items[n-1]
        if n < len(items) - 1:
            item.next = items[n+1]

        log.debug(f"Processing item {n}/{len(items)}:  {item}")
        item.mk_output()
        item.mk_thumb()

    [log.debug("item: %s", i) for i in items]

    # Apparently jinja doesn't like absolute paths?
    env = jinja2.Environment(loader=jinja2.FileSystemLoader([".", os.path.dirname(__file__), "/home/karlp/src/make_album"]),
                             autoescape=jinja2.select_autoescape(['html', 'xml']),
                             undefined=jinja2.DebugUndefined)
    env.globals = dict(opts=opts, tripreport=opts.tripreport.read().decode("utf8"))

    tpl_idx = env.get_template(opts.template_index)
    tpl_page = env.get_template(opts.template_picpage)

    nom_pages = len(items) / (opts.rows * opts.cols)
    page_count = math.floor(nom_pages)
    if nom_pages > page_count:
        page_count = page_count + 1

    pages = [Page(i+1, opts) for i in range(page_count)]
    log.info("Creating %d pages of %d rows of %d", page_count, opts.rows, opts.cols)

    items_chunked = list(itertools.zip_longest(*[iter(items)] * (opts.rows * opts.cols)))
    if not os.path.isdir(opts.outdir):
        os.makedirs(opts.outdir)

    for page in pages:
        page.items = [i for i in items_chunked[page.idx-1] if i]

        log.info("Processing page %d which has %d items on it", page.idx, len(page.items))

        with open(f"{opts.outdir}/page_{page.idx}.html", "wb") as fidx:
            fidx.write(tpl_idx.render(title=opts.title, pages=pages, page=page).encode("utf8"))

        for i in page.items:
            if not os.path.isdir(os.path.dirname(i.page_fn)):
                os.mkdir(os.path.dirname(i.page_fn))
            with open(i.page_fn, "wb") as fpic:
                fpic.write(tpl_page.render(item=i).encode("utf8"))


if __name__ == "__main__":
    myopts = get_args()
    do_main(myopts)
