#!/usr/bin/env bash
# Generate the ReadAloud app icon set.
#
# Renders a 1024x1024 base PNG via Core Graphics (a rounded-square coral
# background with a white speaker-wave glyph), then fans out to every size
# the AppIcon.appiconset expects. Idempotent — re-run any time.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_SET="${REPO_ROOT}/ReadAloud/Resources/Assets.xcassets/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BASE_PNG="${TMP_DIR}/icon-1024.png"

echo "==> Rendering base icon at ${BASE_PNG}"
swift - <<'SWIFT' "${BASE_PNG}"
import AppKit
import CoreImage

guard CommandLine.arguments.count >= 2 else { exit(2) }
let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Background — diagonal coral gradient that pops on both light and dark wallpapers.
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let corner: CGFloat = size * 0.224  // matches Apple "squircle" radius
let mask = NSBezierPath(roundedRect: bgRect, xRadius: corner, yRadius: corner)
mask.addClip()

let gradient = NSGradient(starting: NSColor(srgbRed: 1.00, green: 0.42, blue: 0.31, alpha: 1),
                          ending:   NSColor(srgbRed: 0.96, green: 0.27, blue: 0.46, alpha: 1))!
gradient.draw(in: bgRect, angle: 315)

// Speaker glyph + sound waves, hand-drawn for crispness at every size.
NSColor.white.setFill()
NSColor.white.setStroke()

let center = NSPoint(x: size * 0.40, y: size * 0.50)

// Speaker cone — a trapezoid plus its rectangle body.
let body = NSBezierPath()
let bodyHalfH = size * 0.10
let bodyW = size * 0.08
let coneHalfH = size * 0.21
let coneRight = center.x + size * 0.15
body.move(to: NSPoint(x: center.x - bodyW, y: center.y - bodyHalfH))
body.line(to: NSPoint(x: center.x - bodyW, y: center.y + bodyHalfH))
body.line(to: NSPoint(x: center.x,         y: center.y + bodyHalfH))
body.line(to: NSPoint(x: coneRight,        y: center.y + coneHalfH))
body.line(to: NSPoint(x: coneRight,        y: center.y - coneHalfH))
body.line(to: NSPoint(x: center.x,         y: center.y - bodyHalfH))
body.close()
body.fill()

// Three concentric sound waves on the right side.
let waveCenter = NSPoint(x: coneRight, y: center.y)
let waveLineWidth = size * 0.04
let halfArc: CGFloat = 50  // ± degrees from horizontal
for i in 0..<3 {
    let radius = size * (0.10 + CGFloat(i) * 0.07)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: waveCenter,
                  radius: radius,
                  startAngle: -halfArc,
                  endAngle: halfArc)
    arc.lineWidth = waveLineWidth
    arc.lineCapStyle = .round
    arc.stroke()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

if [[ ! -f "${BASE_PNG}" ]]; then
    echo "Base icon was not produced." >&2
    exit 1
fi

# Pairs of (filename, pixel size) — pixel size includes scale (e.g. 32x32@2x → 64px).
emit() {
    local target="$1" px="$2"
    sips -z "${px}" "${px}" "${BASE_PNG}" --out "${ICON_SET}/${target}" >/dev/null
}

echo "==> Generating icon sizes"
emit "icon_16x16.png"        16
emit "icon_16x16@2x.png"     32
emit "icon_32x32.png"        32
emit "icon_32x32@2x.png"     64
emit "icon_128x128.png"      128
emit "icon_128x128@2x.png"   256
emit "icon_256x256.png"      256
emit "icon_256x256@2x.png"   512
emit "icon_512x512.png"      512
emit "icon_512x512@2x.png"   1024

cat > "${ICON_SET}/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",       "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",       "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",    "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",     "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",     "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",     "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png",  "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "==> Wrote 10 PNGs + Contents.json to ${ICON_SET}"
