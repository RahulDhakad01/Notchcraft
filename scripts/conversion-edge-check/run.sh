#!/bin/bash
# Edge cases for the file conversions that don't go through the PDF → Word engine:
# metadata on pictures, multi-page TIFF, damaged / empty / password-protected files, CSV encodings,
# Excel number formats, Markdown, HTML encodings, and (with Microsoft Office installed) the Office routes.
#
#   scripts/conversion-edge-check/run.sh
#
# Prints one line per case. The deliberately broken files are expected to FAIL with a plain explanation.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/Sources/NotchCraft"
WORK="${CONVERSION_EDGE_DIR:-$ROOT/.build/conversion-edge-check}"
FILES="$WORK/files"; OUT="$WORK/out-$(date +%H%M%S)"
mkdir -p "$FILES" "$OUT" "$WORK/bin"

echo "Creating test files…"
cp "$HERE/rich.md" "$FILES/"
# Pictures: a 2-page TIFF from a generated PNG.
/usr/bin/python3 -I - "$FILES" <<'PY'
import sys, zlib, struct, zipfile, os
d = sys.argv[1]
def png(path, w=200, h=120):
    raw = b''.join(b'\x00' + bytes([40, 120, 220]) * w for _ in range(h))
    def chunk(t, c): return struct.pack('>I', len(c)) + t + c + struct.pack('>I', zlib.crc32(t + c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
png(os.path.join(d, 'page.png'))
open(os.path.join(d, 'empty.pdf'), 'wb').close()
open(os.path.join(d, 'bad.pdf'), 'w').write('this is not a pdf')
open(os.path.join(d, 'fake.docx'), 'w').write('not really a word file')
open(os.path.join(d, 'locked.xlsx'), 'wb').write(b'\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1garbage')
open(os.path.join(d, 'win1252.csv'), 'wb').write('name,city,amount\nJosé,Zürich,12\nMüller,Köln,7\n'.encode('cp1252'))
open(os.path.join(d, 'utf16.csv'), 'wb').write('name;city;amount\nÅsa;Göteborg;1\nZoë;Köln;2\n'.encode('utf-16'))
open(os.path.join(d, 'latin.html'), 'wb').write('<html><head><meta charset="windows-1252"></head><body><h1>Café menu</h1><p>Crème brûlée</p></body></html>'.encode('cp1252'))
S = '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
rows = [('noise', '0.30000000000000004', 0), ('percent', '0.15', 1), ('2 decimals', '3.14159', 2), ('0.0%', '0.12345', 3), ('date', '46000', 4)]
S += '<row r="1"><c r="A1" t="inlineStr"><is><t>kind</t></is></c><c r="B1" t="inlineStr"><is><t>value</t></is></c></row>'
for i, (k, v, s) in enumerate(rows, start=2):
    S += f'<row r="{i}"><c r="A{i}" t="inlineStr"><is><t>{k}</t></is></c><c r="B{i}" s="{s}"><v>{v}</v></c></row>'
S += '</sheetData></worksheet>'
styles = '<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="0.0%"/></numFmts><cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="9"/><xf numFmtId="2"/><xf numFmtId="164"/><xf numFmtId="14"/></cellXfs></styleSheet>'
wb = '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Fmt" sheetId="1" r:id="rId1"/></sheets></workbook>'
ct = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>'
rels = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
wrels = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
with zipfile.ZipFile(os.path.join(d, 'fmt.xlsx'), 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in [('[Content_Types].xml', ct), ('_rels/.rels', rels), ('xl/workbook.xml', wb), ('xl/_rels/workbook.xml.rels', wrels), ('xl/worksheets/sheet1.xml', S), ('xl/styles.xml', styles)]:
        z.writestr(name, data)
# A wide sheet, to test the Excel PDF export.
def col(i):
    s = ''; i += 1
    while i: i, r = divmod(i - 1, 26); s = chr(65 + r) + s
    return s
rows = ''.join('<row r="%d">%s</row>' % (r, ''.join('<c r="%s%d" t="inlineStr"><is><t>R%dC%d value</t></is></c>' % (col(c), r, r, c + 1) for c in range(30))) for r in range(1, 41))
sheet = '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>%s</sheetData></worksheet>' % rows
# Excel itself opens this one, so it needs the full content-type list.
ct_full = ct.replace('</Types>', '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
with zipfile.ZipFile(os.path.join(d, 'wide.xlsx'), 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in [('[Content_Types].xml', ct_full), ('_rels/.rels', rels), ('xl/workbook.xml', wb.replace('Fmt', 'Wide')), ('xl/_rels/workbook.xml.rels', wrels), ('xl/worksheets/sheet1.xml', sheet)]:
        z.writestr(name, data)
PY
tiffutil -cat "$FILES/page.png" "$FILES/page.png" -out "$FILES/multi.tiff" >/dev/null 2>&1 || sips -s format tiff "$FILES/page.png" --out "$FILES/multi.tiff" >/dev/null 2>&1

echo "Building…"
SOURCES=()
for f in "$SRC/Conversion"/*.swift "$SRC/Conversion/PDFToDocx"/*.swift; do
  case "$f" in *ConversionFeature.swift) continue;; esac
  SOURCES+=("$f")
done
SOURCES+=("$SRC/TrayManagedStorage.swift" "$HERE/stubs.swift")
mkdir -p "$WORK/main" && cp "$HERE/harness.swift" "$WORK/main/main.swift"
swiftc -O -o "$WORK/bin/edge" "${SOURCES[@]}" "$WORK/main/main.swift" 2>&1 | grep -E "error" && exit 2

echo; "$WORK/bin/edge" "$FILES" "$OUT" 2>&1 | grep -v -E "attributedStringScaled|CFURL"
echo; echo "Outputs: $OUT"
