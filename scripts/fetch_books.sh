#!/usr/bin/env bash
# Tải bộ sách miễn phí (Project Gutenberg, đã hết bản quyền) để đóng gói vào app.
# Tệp được đặt tên "<chu_de>__<id>.epub" trong DocSach/SeedBooks/.
set -u
cd "$(dirname "$0")/.."
OUT=DocSach/SeedBooks
mkdir -p "$OUT"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
ok=0; fail=0
while IFS=$'\t' read -r cat id note; do
  [[ -z "${cat}" || "${cat}" == \#* ]] && continue
  dest="$OUT/${cat}__${id}.epub"
  got=""
  for url in "https://www.gutenberg.org/ebooks/${id}.epub3.images" \
             "https://www.gutenberg.org/cache/epub/${id}/pg${id}-images-3.epub" \
             "https://gutenberg.pglaf.org/cache/epub/${id}/pg${id}-images-3.epub" \
             "https://aleph.gutenberg.org/cache/epub/${id}/pg${id}-images-3.epub" \
             "https://mirror.csclub.uwaterloo.ca/gutenberg/cache/epub/${id}/pg${id}-images-3.epub" \
             "https://gutenberg.pglaf.org/cache/epub/${id}/pg${id}-images.epub" \
             "https://aleph.gutenberg.org/cache/epub/${id}/pg${id}-images.epub"; do
    if curl -fsSL --retry 2 --retry-delay 3 --max-time 120 -A "$UA" -o "$dest" "$url" 2>/dev/null \
       && [ "$(head -c 2 "$dest")" = "PK" ]; then got=1; break; fi
  done
  if [ -n "$got" ]; then
    title=$(unzip -p "$dest" '*.opf' 2>/dev/null | tr '\n' ' ' | sed -n 's/.*<dc:title[^>]*>\([^<]*\)<.*/\1/p' | head -c 100)
    echo "OK   [$url] ${cat}  #${id}  $(du -h "$dest" | cut -f1)  -> ${title}   (mong doi: ${note})"
    ok=$((ok+1))
  else
    rm -f "$dest"; echo "FAIL ${cat}  #${id}  ${note}"; fail=$((fail+1))
  fi
  sleep 1
done < scripts/seed_books.tsv

# --- Sách tiếng Việt đã hết bản quyền: Wikisource tiếng Việt, xuất EPUB bằng WS Export ---
i=0
while IFS=$'\t' read -r cat q; do
  [[ -z "${cat}" || "${cat}" == \#* ]] && continue
  i=$((i+1))
  title=$(curl -fsSL -G -A "$UA" "https://vi.wikisource.org/w/api.php" \
      --data-urlencode "action=query" --data-urlencode "list=search" --data-urlencode "srsearch=${q}" \
      --data-urlencode "srnamespace=0" --data-urlencode "srlimit=5" --data-urlencode "format=json" 2>/dev/null \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["query"]["search"]; print(r[0]["title"].split("/")[0] if r else "")' 2>/dev/null)
  if [ -z "$title" ]; then echo "FAIL vi ${cat} '${q}': khong tim thay"; fail=$((fail+1)); continue; fi
  dest="$OUT/${cat}__vi$(printf '%02d' $i).epub"
  if curl -fsSL -G --max-time 300 -A "$UA" "https://ws-export.wmcloud.org/" \
       --data-urlencode "format=epub-3" --data-urlencode "lang=vi" --data-urlencode "page=${title}" -o "$dest" \
     && [ "$(head -c 2 "$dest")" = "PK" ]; then
    echo "OK   vi ${cat} '${q}' -> trang '${title}' $(du -h "$dest" | cut -f1)"; ok=$((ok+1))
  else
    rm -f "$dest"; echo "FAIL vi ${cat} '${q}' -> trang '${title}': WS Export loi"; fail=$((fail+1))
  fi
  sleep 2
done < scripts/seed_books_vi.tsv

echo "Tong: ${ok} cuon OK, ${fail} loi"
