// Turns Design/icon-source.png into the app icon iOS needs: 1024×1024 and fully opaque.
// Run from the repo root:  swift Design/make-icon.swift

import AppKit

let size = 1024
let source = NSImage(contentsOfFile: "Design/icon-source.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// iOS shows transparent parts of an icon as black, so fill behind the artwork with white.
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.interpolationQuality = .high
context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "Shared/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
print("Wrote Shared/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
