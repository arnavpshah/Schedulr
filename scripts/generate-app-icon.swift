#!/usr/bin/env swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let outPath = "/Users/arnavshah/Desktop/Schedulr/Schedulr/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no cg context")
}

// --- Pure black background ---
ctx.setFillColor(NSColor.black.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// --- Three rounded bars: schedule/list mark, decreasing length, centered ---
let barH: CGFloat = 44
let radius: CGFloat = barH / 2
let widths: [CGFloat] = [380, 300, 220]
let spacing: CGFloat = 96
let centerX = size / 2
let centerY = size / 2
let totalH = CGFloat(widths.count - 1) * spacing
let topCenterY = centerY + totalH / 2

ctx.setFillColor(NSColor.white.cgColor)
for (i, w) in widths.enumerated() {
    let cy = topCenterY - CGFloat(i) * spacing
    let rect = CGRect(x: centerX - w / 2, y: cy - barH / 2, width: w, height: barH)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.fillPath()
}

img.unlockFocus()

// --- Save PNG (opaque) ---
guard let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("png encode failed")
}

try pngData.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(pngData.count) bytes)")
