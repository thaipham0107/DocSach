#!/usr/bin/env python3
"""Tạo EPUB từ một tác phẩm trên Wikisource tiếng Việt (văn bản đã hết bản quyền).
Cách dùng: python3 wikisource_epub.py "<tên trang>" <tệp ra.epub> [chu_de]
In ra tên trang thực tế và số chương. Thoát mã 1 nếu không có trang."""
import json, re, sys, time, uuid, zipfile, urllib.parse, urllib.request, html
from bs4 import BeautifulSoup

API = "https://vi.wikisource.org/w/api.php"
UA = "DocSach-build/1.0 (personal e-reader; github.com/thaipham0107/DocSach)"

def api(**params):
    params.update(format="json", formatversion="2")
    url = API + "?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:
            time.sleep(2 + attempt * 3)
            err = e
    raise err

def resolve_title(q):
    d = api(action="query", titles=q, redirects=1)
    pages = d.get("query", {}).get("pages", [])
    if pages and not pages[0].get("missing"):
        return pages[0]["title"]
    return None

def parse(title):
    d = api(action="parse", page=title, prop="text|displaytitle", redirects=1, disableeditsection=1)
    if "error" in d:
        return None
    return d["parse"]["title"], d["parse"]["text"]

def clean(html_text):
    soup = BeautifulSoup(html_text, "html.parser")
    for sel in ["style", "script", "link", "meta", "img", "sup.reference", ".mw-editsection",
                ".noprint", ".ws-noexport", ".ws-header", "#headertemplate", ".headertemplate",
                "table.header", ".navbox", ".licenseContainer", ".licenseBanner", ".mw-references-wrap"]:
        for el in soup.select(sel):
            el.decompose()
    for a in soup.find_all("a"):
        a.unwrap()
    return soup

def xhtml(title, body_html):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="vi" lang="vi"><head><meta charset="utf-8"/>'
            f'<title>{html.escape(title)}</title></head><body><h2>{html.escape(title)}</h2>{body_html}</body></html>')

def to_xhtml_fragment(soup):
    # Chuẩn hoá thành XHTML hợp lệ (thẻ rỗng tự đóng)
    s = str(soup)
    s = re.sub(r"<(br|hr)([^>]*?)/?>", r"<\1\2/>", s)
    s = s.replace("&nbsp;", "&#160;")
    return s

def main():
    query, out = sys.argv[1], sys.argv[2]
    title = resolve_title(query)
    if not title:
        print(f"khong co trang '{query}'"); sys.exit(1)
    main_title, main_html = parse(title)
    soup = BeautifulSoup(main_html, "html.parser")
    # Các chương: liên kết tới trang con "Tên/…" theo thứ tự xuất hiện
    prefix = "/wiki/" + urllib.parse.quote(title.replace(" ", "_")) + "/"
    subs = []
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith(prefix):
            t = urllib.parse.unquote(href[len("/wiki/"):]).split("#")[0].replace("_", " ")
            if t not in subs:
                subs.append(t)
    if not subs:
        d = api(action="query", list="allpages", apprefix=title + "/", apnamespace=0, aplimit="max")
        subs = [p["title"] for p in d.get("query", {}).get("allpages", [])]
        subs.sort(key=lambda t: [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", t)])

    chapters = []
    if subs:
        intro = clean(main_html)
        text = intro.get_text(" ", strip=True)
        for sub in subs[:200]:
            r = parse(sub)
            if not r: continue
            ct, chtml = r
            body = clean(chtml)
            if len(body.get_text(strip=True)) < 20: continue
            chapters.append((ct.split("/", 1)[-1], to_xhtml_fragment(body)))
            time.sleep(0.3)
    if not chapters:
        chapters = [(main_title, to_xhtml_fragment(clean(main_html)))]

    # Tác giả: lấy từ khối đầu trang nếu có
    author = ""
    m = re.search(r'class="[^"]*(?:ws-author|author)[^"]*"[^>]*>(.*?)</', main_html, re.S)
    if m:
        author = re.sub("<[^>]+>", "", m.group(1)).strip()

    book_id = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "vi.wikisource:" + title))
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
                   '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                   '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        manifest, spine, navli = [], [], []
        for i, (ct, body) in enumerate(chapters, 1):
            name = f"c{i:03d}.html"  # .html: WebKit đọc dễ dãi, tránh lỗi XHTML
            z.writestr("OEBPS/" + name, xhtml(ct, body), compress_type=zipfile.ZIP_DEFLATED)
            manifest.append(f'<item id="c{i}" href="{name}" media-type="application/xhtml+xml"/>')
            spine.append(f'<itemref idref="c{i}"/>')
            navli.append(f'<li><a href="{name}">{html.escape(ct)}</a></li>')
        nav = ('<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml" '
               'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Mục lục</title></head><body>'
               f'<nav epub:type="toc"><ol>{"".join(navli)}</ol></nav></body></html>')
        z.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        opf = ('<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bid">'
               '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
               f'<dc:identifier id="bid">{book_id}</dc:identifier><dc:title>{html.escape(main_title)}</dc:title>'
               f'<dc:creator>{html.escape(author)}</dc:creator><dc:language>vi</dc:language>'
               '<dc:subject>Văn học Việt Nam</dc:subject><dc:source>vi.wikisource.org</dc:source></metadata>'
               '<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
               + "".join(manifest) + '</manifest><spine>' + "".join(spine) + '</spine></package>')
        z.writestr("OEBPS/content.opf", opf, compress_type=zipfile.ZIP_DEFLATED)
    print(f"'{main_title}' tac gia='{author}' {len(chapters)} chuong")

if __name__ == "__main__":
    main()
