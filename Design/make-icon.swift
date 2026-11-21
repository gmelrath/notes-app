// Updates the fox layer of the app icon from Design/icon.svg.
//
// The app icon is App/AppIcon.icon, an Icon Composer file: open it in Icon Composer (inside Xcode) to
// see or adjust it. It has two parts:
// - the navy background, a colour set in AppIcon.icon/icon.json;
// - the fox and box, the image AppIcon.icon/Assets/fox.png, which this script makes.
// iOS draws the Default, Dark, Tinted and Clear looks from those, and Xcode makes the plain images
// older iOS versions need.
//
// To change the artwork, replace Design/icon.svg and run from the repo root:  swift Design/make-icon.swift
// If the background colour changes too, update "fill" in icon.json (or in Icon Composer).

import AppKit

let size = 1024
let output = "App/AppIcon.icon/Assets/fox.png"
let svg = try! String(contentsOfFile: "Design/icon.svg", encoding: .utf8)

// The background is the full-size rectangle the SVG draws first. Leaving it out gives the fox and box alone.
let background = try! NSRegularExpression(pattern: ##"<rect width="512" height="512" fill="#[0-9A-Fa-f]{6}"/>"##)
let fullRange = NSRange(svg.startIndex..., in: svg)
guard background.numberOfMatches(in: svg, range: fullRange) == 1 else {
    fatalError("Couldn't find the icon's background rectangle in Design/icon.svg")
}
let artwork = NSImage(data: Data(background.stringByReplacingMatches(in: svg, range: fullRange, withTemplate: "").utf8))!
    .cgImage(forProposedRect: nil, context: nil, hints: nil)!

let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high
context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
