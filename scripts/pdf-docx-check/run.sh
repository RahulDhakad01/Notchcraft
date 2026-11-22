#!/bin/bash
# PDF → Word quality check.
#
#   scripts/pdf-docx-check/run.sh               build the HTML fixtures with Chrome and test them
#   scripts/pdf-docx-check/run.sh a.pdf b.pdf   test your own PDFs
#
# For each PDF: convert it with the app's converter, open the .docx in Microsoft Word, export that
# to PDF, and compare it with the original: page count, how many words survive, and how far the
# lines and boxes moved. Side-by-side pictures (original | converted | difference) are written
# next to the results. Needs Microsoft Word; the HTML fixtures also need Google Chrome.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/Sources/NotchCraft/Conversion/PDFToDocx"
OUT="${PDF_DOCX_CHECK_DIR:-$ROOT/.build/pdf-docx-check}"
mkdir -p "$OUT/bin" "$OUT/work"

[ -d "/Applications/Microsoft Word.app" ] || { echo "Microsoft Word is needed to render the converted files."; exit 2; }

SOURCES=("$SRC"/*.swift "$HERE/tools/stubs.swift")

echo "Building tools…"
# A tool with top-level code must be called main.swift when it is built with other files.
mkdir -p "$OUT/work/convert" "$OUT/work/segdiff"
cp "$HERE/tools/convert.swift" "$OUT/work/convert/main.swift"
cp "$HERE/tools/segdiff.swift" "$OUT/work/segdiff/main.swift"
swiftc -O -o "$OUT/bin/convert" "${SOURCES[@]}" "$OUT/work/convert/main.swift" 2>&1 | grep -E "error" && exit 2
swiftc -O -o "$OUT/bin/compare" "$HERE/tools/compare.swift" 2>&1 | grep -E "error" && exit 2
SEG_SOURCES=("$SRC/PDFContentStream.swift" "$SRC/PDFLayoutModel.swift" "$SRC/PDFFont.swift" "$SRC/PDFVectorScanner.swift" "$SRC/PDFTextExtractor.swift")
swiftc -O -o "$OUT/bin/segdiff" "${SEG_SOURCES[@]}" "$OUT/work/segdiff/main.swift" 2>&1 | grep -E "error" && exit 2

PDFS=("$@")
if [ ${#PDFS[@]} -eq 0 ]; then
  CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$CHROME" ] || { echo "Google Chrome is needed to build the fixtures (or pass your own PDFs)."; exit 2; }
  # A small picture for the report fixture.
  sips -s format png -Z 240 "$ROOT/Sources/NotchCraft/Resources/AppIcon.icns" --out "$OUT/work/picture.png" >/dev/null 2>&1
  IMG="data:image/png;base64,$(base64 -i "$OUT/work/picture.png" | tr -d '\n')"
  for name in simple columns report; do
    sed "s|IMAGE_DATA_URI|$IMG|" "$HERE/fixtures/$name.html" > "$OUT/work/$name.html"
    "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$OUT/work/$name.pdf" "file://$OUT/work/$name.html" >/dev/null 2>&1
    PDFS+=("$OUT/work/$name.pdf")
  done
fi

FAILED=0
for pdf in "${PDFS[@]}"; do
  name="$(basename "$pdf" .pdf)"
  echo
  echo "── $name"
  if ! "$OUT/bin/convert" "$pdf" "$OUT/work/$name.docx" > "$OUT/work/$name.log" 2>&1; then
    cat "$OUT/work/$name.log"; echo "FAIL: conversion error"; FAILED=1; continue
  fi
  grep -E "^pages|coverage|warning" "$OUT/work/$name.log"
  "$HERE/docx-to-pdf.sh" "$OUT/work/$name.docx" "$OUT/work/$name-word.pdf" || { echo "FAIL: Word could not open the result"; FAILED=1; continue; }
  "$OUT/bin/compare" "$pdf" "$OUT/work/$name-word.pdf" "$OUT/work/$name-compare" | tee "$OUT/work/$name.compare" | grep -E "^pages|word match|^page "
  "$OUT/bin/segdiff" "$pdf" "$OUT/work/$name-word.pdf" | head -2

  pages_line=$(grep "^pages:" "$OUT/work/$name.compare" | head -1)
  orig=$(echo "$pages_line" | sed -E 's/.*original ([0-9]+).*/\1/'); conv=$(echo "$pages_line" | sed -E 's/.*converted ([0-9]+).*/\1/')
  words=$(grep "word match" "$OUT/work/$name.compare" | sed -E 's/.*: ([0-9.]+)%.*/\1/')
  worst=$(grep -E "^page [0-9]+:" "$OUT/work/$name.compare" | sed -E 's/.*block diff ([0-9.]+)%.*/\1/' | sort -n | tail -1)
  ok=1
  [ "$orig" = "$conv" ] || { echo "FAIL: page count $orig → $conv"; ok=0; }
  awk -v w="$words" 'BEGIN { exit !(w >= 95) }' || { echo "FAIL: only $words% of words survived"; ok=0; }
  awk -v d="${worst:-0}" 'BEGIN { exit !(d <= 6) }' || { echo "FAIL: layout differs by $worst%"; ok=0; }
  [ $ok = 1 ] && echo "PASS" || FAILED=1
done
echo
echo "Pictures and files: $OUT/work"
exit $FAILED
