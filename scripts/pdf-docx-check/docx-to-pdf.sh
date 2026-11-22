#!/bin/bash
# docx-to-pdf.sh <in.docx> <out.pdf> — renders a .docx through Microsoft Word, the reference renderer.
set -e
IN="$1"; OUT="$2"
GROUP="$HOME/Library/Group Containers/UBF8T346G9.Office/NotchCraft-Convert/check-$$"
mkdir -p "$GROUP"
trap 'rm -rf "$GROUP"' EXIT
cp "$IN" "$GROUP/in.docx"
xattr -c "$GROUP/in.docx" 2>/dev/null || true
cat > "$GROUP/render.applescript" <<SCRIPT
tell application "Microsoft Word"
    open POSIX file "$GROUP/in.docx" read only true confirm conversions false add to recent files false
    set theDocument to active document
    save as theDocument file name "$GROUP/out.pdf" file format format PDF
    close theDocument saving no
end tell
SCRIPT
osascript "$GROUP/render.applescript" >/dev/null
cp "$GROUP/out.pdf" "$OUT"
