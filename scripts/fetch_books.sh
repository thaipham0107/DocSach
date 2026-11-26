#!/usr/bin/env bash
# Tải bộ sách miễn phí (Project Gutenberg, đã hết bản quyền) để đóng gói vào app.
# Tệp được đặt tên "<chu_de>__<id>.epub" trong DocSach/SeedBooks/.
set -u
cd "$(dirname "$0")/.."
OUT=DocSach/SeedBooks
mkdir -p "$OUT"
ok=0; fail=0
while IFS=$'\t' read -r cat id note; do
  [[ -z "${cat}" || "${cat}" == \#* ]] && continue
  dest="$OUT/${cat}__${id}.epub"
  got=""
  for url in "https://www.gutenberg.org/ebooks/${id}.epub3.images" \
             "https://www.gutenberg.org/ebooks/${id}.epub.images" \
             "https://www.gutenberg.org/cache/epub/${id}/pg${id}-images-3.epub"; do
    if curl -fsSL --retry 3 --max-time 120 -A "DocSach-build/1.0" -o "$dest" "$url" \
       && [ "$(head -c 2 "$dest")" = "PK" ]; then got=1; break; fi
  done
  if [ -n "$got" ]; then
    title=$(unzip -p "$dest" '*.opf' 2>/dev/null | tr '\n' ' ' | sed -n 's/.*<dc:title[^>]*>\([^<]*\)<.*/\1/p' | head -c 100)
    echo "OK   ${cat}  #${id}  $(du -h "$dest" | cut -f1)  -> ${title}   (mong doi: ${note})"
    ok=$((ok+1))
  else
    rm -f "$dest"; echo "FAIL ${cat}  #${id}  ${note}"; fail=$((fail+1))
  fi
  sleep 1
done < scripts/seed_books.tsv
echo "Tong: ${ok} cuon OK, ${fail} loi"
