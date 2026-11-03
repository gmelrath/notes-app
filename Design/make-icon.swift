// Turns Design/icon-source.png into the app icon iOS needs: 1024×1024, fully opaque, on the
// same light gray as the app's pages. Run from the repo root:  swift Design/make-icon.swift

import AppKit

let size = 1024
let source = NSImage(contentsOfFile: "Design/icon-source.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// iOS shows transparent parts of an icon as black, so fill behind the artwork with white.
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.interpolationQuality = .high
context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

// The source has a white background with soft shadows. Tint that background (found by spreading
// in from the edges over light, colourless pixels) to the pages' gray, #F2F2F7, by multiplying,
// so the shadows keep their shape. The artwork itself is left as it is.
let gray: [Double] = [0xF2, 0xF2, 0xF7].map { Double($0) / 255 }
let pixels = context.data!.bindMemory(to: UInt8.self, capacity: size * size * 4)
func isBackground(_ i: Int) -> Bool {
    let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
    return min(r, g, b) >= 200 && max(r, g, b) - min(r, g, b) <= 16
}
var visited = [Bool](repeating: false, count: size * size)
var stack = (0..<size).flatMap { [$0, (size - 1) * size + $0, $0 * size, $0 * size + size - 1] }
while let i = stack.popLast() {
    guard !visited[i], isBackground(i) else { continue }
    visited[i] = true
    for channel in 0..<3 {
        pixels[i * 4 + channel] = UInt8((Double(pixels[i * 4 + channel]) * gray[channel]).rounded())
    }
    let x = i % size, y = i / size
    if x > 0 { stack.append(i - 1) }
    if x < size - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - size) }
    if y < size - 1 { stack.append(i + size) }
}

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "Shared/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
print("Wrote Shared/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
