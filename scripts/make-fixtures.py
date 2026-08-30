#!/usr/bin/env python3
"""Generate synthetic AO3-style EPUBs for development fixtures.

Mirrors the structure of real AO3 exports (content.opf + preface xhtml with
the dl.tags block) so Parade's metadata parser sees realistic variety
without downloading anyone's actual fic.

Usage: make-fixtures.py <output-dir>   # writes <Author>/<Title>.epub trees
"""
import sys, zipfile, html
from pathlib import Path

FICS = [
    # title, author, fandoms, category, rating, series(name, part), tags, words, chapters, summary
    ("The Long Way Round", "quillheart", ["Harry Potter - J. K. Rowling"], "F/M",
     "Teen And Up Audiences", ("Postwar Letters", 1), ["Slow Burn", "Epistolary"],
     "48,213", "12/12", "Letters across a war that ended but didn't."),
    ("Paper Cranes", "quillheart", ["Harry Potter - J. K. Rowling"], "F/M",
     "General Audiences", ("Postwar Letters", 2), ["Fluff", "Domestic"],
     "22,108", "6/6", "A thousand cranes, one wish."),
    ("Ward Rounds", "nightshift_rn", ["House M.D."], "Gen",
     "General Audiences", None, ["Case Fic", "Team Dynamics"],
     "9,412", "3/3", "Three impossible cases, one long weekend."),
    ("Static", "nightshift_rn", ["House M.D."], "M/M",
     "Mature", ("Frequencies", 1), ["Angst", "Miscommunication"],
     "31,077", "8/?", "Wilson stops answering his pager."),
    ("Signal", "nightshift_rn", ["House M.D."], "M/M",
     "Mature", ("Frequencies", 2), ["Angst with a Happy Ending"],
     "18,555", "5/5", "The pager was never the problem."),
    ("Hyperspace Lullaby", "corellian_exile", ["Star Wars - All Media Types"], "F/F",
     "General Audiences", None, ["Found Family", "Space Pirates"],
     "12,930", "4/4", "A stolen freighter, a sleeping child, a course for nowhere."),
    ("Cloudless", "corellian_exile", ["Star Wars - All Media Types", "Star Wars: The Clone Wars"], "Gen",
     "Teen And Up Audiences", None, ["Time Travel", "Fix-It"],
     "76,401", "20/24", "Ahsoka wakes up on the day everything went wrong."),
    ("Tea Leaves", "jadelotus", ["Mo Dao Zu Shi"], "M/M",
     "Explicit", ("Cloud Recesses Vignettes", 1), ["Pining", "Getting Together"],
     "27,845", "7/7", "Sixteen years of unsent letters, one pot of tea."),
    ("Ink Stones", "jadelotus", ["Mo Dao Zu Shi"], "M/M",
     "Explicit", ("Cloud Recesses Vignettes", 2), ["Established Relationship"],
     "15,220", "4/4", "The calligraphy lessons were a pretext."),
    ("Second Breakfast", "tookishness", ["The Lord of the Rings - J. R. R. Tolkien"], "Gen",
     "General Audiences", None, ["Hobbits", "Food", "Fluff"],
     "5,912", "1/1", "The quest can wait until after elevenses."),
]

PREFACE = """<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>{title}</title></head>
<body>
<div id="preface">
  <p class="message"><b>{title}</b><br/>
  Posted originally on the <a href="https://archiveofourown.org/">Archive of Our Own</a> at <a href="https://archiveofourown.org/works/{work_id}">https://archiveofourown.org/works/{work_id}</a>.</p>
  <div><dl class="tags">
    <dt>Rating:</dt><dd><a href="#">{rating}</a></dd>
    <dt>Archive Warning:</dt><dd><a href="#">No Archive Warnings Apply</a></dd>
    <dt>Category:</dt><dd><a href="#">{category}</a></dd>
    <dt>Fandom:</dt><dd>{fandom_links}</dd>
    <dt>Additional Tags:</dt><dd>{tag_links}</dd>
    {series_block}
    <dt>Stats:</dt><dd>
      Published: 2026-01-15
      Words: {words}
      Chapters: {chapters}
    </dd>
  </dl></div>
</div>
<div class="userstuff"><p>{summary}</p><p>(Synthetic fixture fic — generated for development, not a real work.)</p></div>
</body></html>"""

OPF = """<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>{title}</dc:title>
    <dc:language>en</dc:language>
    <dc:creator opf:role="aut">{author}</dc:creator>
    <dc:description>{summary_escaped}</dc:description>
    <dc:publisher>Archive of Our Own</dc:publisher>
    <dc:identifier id="uuid_id" opf:scheme="uuid">fixture-{work_id}</dc:identifier>
  </metadata>
  <manifest>
    <item id="p0" href="preface.xhtml" media-type="application/xhtml+xml"/>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  </manifest>
  <spine toc="ncx"><itemref idref="p0"/></spine>
</package>"""

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>"""

NCX = """<?xml version='1.0' encoding='utf-8'?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap><navPoint id="n1" playOrder="1"><navLabel><text>Preface</text></navLabel><content src="preface.xhtml"/></navPoint></navMap>
</ncx>"""


def links(names):
    return ", ".join(f'<a href="#">{html.escape(n)}</a>' for n in names)


def main(out_root: Path):
    for i, (title, author, fandoms, category, rating, series, tags, words, chapters, summary) in enumerate(FICS):
        work_id = 90000000 + i
        series_block = ""
        if series:
            name, part = series
            series_block = f'<dt>Series:</dt><dd>Part {part} of <a href="#">{html.escape(name)}</a></dd>'
        preface = PREFACE.format(
            title=html.escape(title), work_id=work_id, rating=html.escape(rating),
            category=html.escape(category), fandom_links=links(fandoms),
            tag_links=links(tags), series_block=series_block,
            words=words, chapters=chapters, summary=html.escape(summary))
        opf = OPF.format(
            title=html.escape(title), author=html.escape(author),
            summary_escaped=html.escape(f"<p>{html.escape(summary)}</p>"),
            work_id=work_id)

        dest = out_root / author / f"{title}.epub"
        dest.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
            z.writestr("META-INF/container.xml", CONTAINER)
            z.writestr("content.opf", opf)
            z.writestr("toc.ncx", NCX)
            z.writestr("preface.xhtml", preface)
        print(f"wrote {dest.relative_to(out_root)}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
