#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSlot {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String { "app-icon-\(points)@\(scale)x.png" }
}

let slots = [
    IconSlot(points: 16, scale: 1),
    IconSlot(points: 16, scale: 2),
    IconSlot(points: 32, scale: 1),
    IconSlot(points: 32, scale: 2),
    IconSlot(points: 128, scale: 1),
    IconSlot(points: 128, scale: 2),
    IconSlot(points: 256, scale: 1),
    IconSlot(points: 256, scale: 2),
    IconSlot(points: 512, scale: 1),
    IconSlot(points: 512, scale: 2),
]

let scriptURL = URL(fileURLWithPath: #filePath)
let repositoryRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let lightMasterURL = repositoryRoot.appending(path: "docs/assets/brand/onebox-mark-light.png")
let darkMasterURL = repositoryRoot.appending(path: "docs/assets/brand/onebox-mark-dark.png")
let outputDirectory = repositoryRoot.appending(
    path: "OneBox/App/Assets.xcassets/AppIcon.appiconset",
    directoryHint: .isDirectory
)

guard let lightMaster = NSImage(contentsOf: lightMasterURL) else {
    fatalError("Unable to read light brand master at \(lightMasterURL.path)")
}
guard NSImage(contentsOf: darkMasterURL) != nil else {
    fatalError("Unable to read dark brand master at \(darkMasterURL.path)")
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: slot.pixels,
            pixelsHigh: slot.pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        fatalError("Unable to allocate \(slot.pixels)px icon")
    }

    bitmap.size = NSSize(width: slot.pixels, height: slot.pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create icon graphics context")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = slot.points <= 32 ? .none : .high
    lightMaster.draw(
        in: NSRect(x: 0, y: 0, width: slot.pixels, height: slot.pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(slot.filename)")
    }
    try data.write(to: outputDirectory.appending(path: slot.filename), options: .atomic)
}

print(
    "Generated \(slots.count) AppIcon files from \(lightMasterURL.lastPathComponent) "
        + "after validating the paired dark master"
)
