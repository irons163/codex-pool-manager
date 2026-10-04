import AppKit
import Testing
@testable import CodexPoolManager

@Suite(.serialized)
@MainActor
struct CodexMenuBarIconTests {
    @Test
    func iconUsesNativeMenuBarSizeAndTemplateRendering() {
        let image = CodexMenuBarIcon.image

        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == "CodexPoolManager")
        #expect(image.representations.contains { $0 is NSCustomImageRep })
    }

    @Test(arguments: [18, 36, 54])
    func iconHasTransparentBackgroundAndMonochromeStrokes(pixelSize: Int) throws {
        let bitmap = try render(pixelSize: pixelSize)
        let corners = [(0, 0), (0, pixelSize - 1), (pixelSize - 1, 0), (pixelSize - 1, pixelSize - 1)]
        for (x, y) in corners {
            let color = try #require(bitmap.colorAt(x: x, y: y))
            #expect(color.alphaComponent == 0)
        }

        var visiblePixels = 0
        var coloredPixels = 0
        for y in 0..<pixelSize {
            for x in 0..<pixelSize {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                guard color.alphaComponent > 0 else { continue }
                visiblePixels += 1
                if color.redComponent > 0.001 || color.greenComponent > 0.001 || color.blueComponent > 0.001 {
                    coloredPixels += 1
                }
            }
        }

        #expect(visiblePixels > pixelSize * 2)
        #expect(visiblePixels < pixelSize * pixelSize * 3 / 4)
        #expect(coloredPixels == 0)
        #expect(CodexMenuBarIcon.image.size == NSSize(width: 18, height: 18))
    }

    private func render(pixelSize: Int) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        let rect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        context.cgContext.clear(rect)
        CodexMenuBarIcon.image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        return bitmap
    }
}
