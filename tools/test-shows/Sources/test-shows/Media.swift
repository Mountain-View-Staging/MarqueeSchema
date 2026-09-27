//
//  Media.swift — generated test media: stills (PNG, JPEG, HEIC, WebP, PNG with alpha) and
//  clips (H.264, HEVC) whose every frame carries its index twice — as a 20-block barcode
//  along the top edge (the Surface harness's reader, MarqueeSurface
//  Tests/ConformanceReplay MediaFactory.swift) and as "frame NNN · SS.SS s" (the Studio
//  harness's OCR, MarqueeStudioWeb tools/fixtures/make-editor-fixture.swift).
//
//  Nothing here is read from anywhere: every pixel is drawn. Text is drawn into the pixels
//  with the system UI font — except the style book's assets, which are drawn in the style's
//  own faces (Inter 4.1, registered from the generator's Resources; ExampleStyle.swift).
//  Colours come from a fixed table, so a file looks the same on every run (an encoder's own
//  run-to-run variation aside).
//

import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import WebPSwift

// MARK: - Drawing

enum Draw {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// HSB → sRGB. Hue in turns (0…1).
    static func hsb(_ hue: Double, _ s: Double, _ v: Double, _ a: CGFloat = 1) -> CGColor {
        let h6 = (hue - hue.rounded(.down)) * 6
        let i = Int(h6.rounded(.down)) % 6
        let f = h6 - h6.rounded(.down)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return rgb(r, g, b, a)
    }

    /// An sRGB RGBA context, y up, cleared to transparent.
    static func context(_ w: Int, _ h: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx
    }

    /// `text` centred on `center`, `size` points tall, in the system UI font.
    static func text(_ text: String, in ctx: CGContext, center: CGPoint, size: CGFloat,
                     color fill: CGColor = rgb(1, 1, 1), weight: CGFloat = 0.4) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let traits = [kCTFontWeightTrait: weight] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
        let weighted = CTFontCreateCopyWithAttributes(font, size, nil, descriptor)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): weighted,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX,
                                   y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    /// `#RRGGBB` → an sRGB colour.
    static func hex(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return rgb(CGFloat((n >> 16) & 255) / 255, CGFloat((n >> 8) & 255) / 255, CGFloat(n & 255) / 255, alpha)
    }

    /// `text` centred on `center` in the face whose PostScript name is `face`, `size` points.
    ///
    /// The face must be registered and must resolve to ITSELF: CoreText answers an unknown
    /// name with Helvetica rather than failing (brand spec §3.1), and a brand asset drawn in
    /// the wrong face says nothing — so this refuses instead of drawing.
    static func text(_ text: String, in ctx: CGContext, center: CGPoint, size: CGFloat,
                     color fill: CGColor, face: String) throws {
        let font = CTFontCreateWithName(face as CFString, size, nil)
        let resolved = CTFontCopyPostScriptName(font) as String
        guard resolved == face else {
            throw GenError.check("the face \(face) is not registered — CoreText answered with \(resolved)")
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): fill,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX,
                                   y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    /// The optical width of `text` in `face` at `size` points.
    static func width(_ text: String, face: String, size: CGFloat) -> CGFloat {
        let font = CTFontCreateWithName(face as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        return CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
    }

    /// Title-safe (90 %) rectangle, a centre cross and a TOP marker: the orientation and
    /// the fit of a still can be read off the screen.
    static func guides(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, ink: CGColor) {
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(max(2, min(w, h) / 360))
        ctx.stroke(CGRect(x: w * 0.05, y: h * 0.05, width: w * 0.9, height: h * 0.9))
        let arm = min(w, h) * 0.04
        ctx.move(to: CGPoint(x: w / 2 - arm, y: h / 2)); ctx.addLine(to: CGPoint(x: w / 2 + arm, y: h / 2))
        ctx.move(to: CGPoint(x: w / 2, y: h / 2 - arm)); ctx.addLine(to: CGPoint(x: w / 2, y: h / 2 + arm))
        ctx.strokePath()
        text("▲ TOP", in: ctx, center: CGPoint(x: w / 2, y: h * 0.965), size: min(w, h) * 0.025, color: ink)
    }
}

// MARK: - The frame barcode

/// The frame index as 20 blocks along the TOP edge: two sync blocks (on, off), 16 data bits
/// MSB first, two sync blocks (off, on). 48 px blocks, centred — a frame at least 960 px wide.
/// Byte-for-byte the layout MarqueeSurface's ConformanceReplay reads.
enum Barcode {
    static let blocks = 20
    static let dataBits = 16
    static let blockWidth = 48
    static let blockHeight = 48

    static func bits(_ index: Int) -> [Bool] {
        [true, false] + (0..<dataBits).map { (index >> (dataBits - 1 - $0)) & 1 == 1 } + [false, true]
    }

    static func draw(_ index: Int, in ctx: CGContext, width: Int, height: Int) {
        let x0 = (width - blocks * blockWidth) / 2
        for (i, bit) in bits(index).enumerated() {
            ctx.setFillColor(bit ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: x0 + i * blockWidth, y: height - blockHeight, width: blockWidth, height: blockHeight))
        }
    }
}

// MARK: - Stills

/// What a still looks like. Every style carries its labels; the alpha styles leave most of
/// the frame transparent.
enum StillStyle {
    /// Colour bars, a dark lower band, title-safe guides.
    case bars
    /// A colour field (hue in turns) with the title large.
    case card(hue: Double)
    /// A smooth two-colour gradient with rings — the "photo" (compresses like one).
    case photo(hue: Double)
    /// Flat bands stepping across the frame — a wallpaper or backing that stays small as a PNG.
    case bands(hue: Double)
    /// Transparent, with a translucent band across the lower third.
    case lowerThird
    /// Transparent, with a frame around a clear window and a band top and bottom — an
    /// overlay that leaves the picture behind it visible.
    case frameOverlay(hue: Double)
    /// Transparent, with a rounded plate reading LOGO.
    case logo
}

struct StillSpec {
    let file: String        // the name the file is imported under (its original name)
    let width: Int
    let height: Int
    let style: StillStyle
    let title: String
    let subtitle: String
    let tag: String         // small print: "<CODE> · <id>"

    var hasAlpha: Bool {
        switch style {
        case .lowerThird, .frameOverlay, .logo: true
        default: false
        }
    }
}

enum Stills {
    static func render(_ spec: StillSpec) -> CGImage {
        let ctx = Draw.context(spec.width, spec.height)
        let W = CGFloat(spec.width), H = CGFloat(spec.height), unit = min(W, H)
        switch spec.style {
        case .bars:
            let palette = [Draw.rgb(0.75, 0.75, 0.75), Draw.rgb(0.75, 0.75, 0), Draw.rgb(0, 0.75, 0.75),
                           Draw.rgb(0, 0.75, 0), Draw.rgb(0.75, 0, 0.75), Draw.rgb(0.75, 0, 0), Draw.rgb(0, 0, 0.75)]
            for (i, c) in palette.enumerated() {
                ctx.setFillColor(c)
                ctx.fill(CGRect(x: W * CGFloat(i) / 7, y: H * 0.33, width: W / 7 + 1, height: H * 0.67))
            }
            ctx.setFillColor(Draw.rgb(0.08, 0.08, 0.1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H * 0.33))
            Draw.guides(ctx, W, H, ink: Draw.rgb(1, 1, 1, 0.9))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.22), size: unit * 0.09, weight: 0.6)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.12), size: unit * 0.035)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W / 2, y: H * 0.07), size: unit * 0.022,
                      color: Draw.rgb(1, 1, 1, 0.7))
        case .card(let hue):
            ctx.setFillColor(Draw.hsb(hue, 0.55, 0.62))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(Draw.hsb(hue, 0.6, 0.45))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H * 0.18))
            Draw.guides(ctx, W, H, ink: Draw.rgb(1, 1, 1, 0.85))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.55), size: unit * 0.12, weight: 0.6)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.42), size: unit * 0.04)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W / 2, y: H * 0.09), size: unit * 0.025,
                      color: Draw.rgb(1, 1, 1, 0.75))
        case .photo(let hue):
            let colors = [Draw.hsb(hue, 0.5, 0.85), Draw.hsb(hue + 0.18, 0.65, 0.35)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
            ctx.setStrokeColor(Draw.rgb(1, 1, 1, 0.18))
            ctx.setLineWidth(unit * 0.01)
            for ring in 1...6 {
                let r = unit * 0.07 * CGFloat(ring)
                ctx.strokeEllipse(in: CGRect(x: W * 0.68 - r, y: H * 0.62 - r, width: 2 * r, height: 2 * r))
            }
            Draw.guides(ctx, W, H, ink: Draw.rgb(1, 1, 1, 0.8))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.3), size: unit * 0.1, weight: 0.6)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.19), size: unit * 0.035)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W / 2, y: H * 0.1), size: unit * 0.022,
                      color: Draw.rgb(1, 1, 1, 0.7))
        case .bands(let hue):
            let steps = 8
            for i in 0..<steps {
                ctx.setFillColor(Draw.hsb(hue + Double(i) * 0.015, 0.5, 0.28 + 0.05 * Double(i)))
                ctx.fill(CGRect(x: W * CGFloat(i) / CGFloat(steps), y: 0, width: W / CGFloat(steps) + 1, height: H))
            }
            Draw.guides(ctx, W, H, ink: Draw.rgb(1, 1, 1, 0.7))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.55), size: unit * 0.09, weight: 0.6)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.44), size: unit * 0.035)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W / 2, y: H * 0.09), size: unit * 0.022,
                      color: Draw.rgb(1, 1, 1, 0.7))
        case .lowerThird:
            let band = CGRect(x: W * 0.05, y: H * 0.09, width: W * 0.57, height: H * 0.14)
            ctx.setFillColor(Draw.rgb(0.05, 0.3, 0.6, 0.85))
            ctx.fill(band)
            ctx.setFillColor(Draw.rgb(1, 0.8, 0.2, 0.95))
            ctx.fill(CGRect(x: band.minX, y: band.minY, width: unit * 0.012, height: band.height))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: band.midX, y: band.midY + band.height * 0.14),
                      size: band.height * 0.34, weight: 0.5)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: band.midX, y: band.midY - band.height * 0.26),
                      size: band.height * 0.18)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W * 0.9, y: H * 0.04), size: unit * 0.02,
                      color: Draw.rgb(1, 1, 1, 0.8))
        case .frameOverlay(let hue):
            // A border around a clear window, with a band top and bottom.
            let ink = Draw.hsb(hue, 0.6, 0.5, 0.92)
            let border = unit * 0.035
            ctx.setFillColor(ink)
            ctx.fill(CGRect(x: 0, y: H - H * 0.1, width: W, height: H * 0.1))        // top band
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H * 0.08))                   // bottom band
            ctx.fill(CGRect(x: 0, y: 0, width: border, height: H))                     // left
            ctx.fill(CGRect(x: W - border, y: 0, width: border, height: H))            // right
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H - H * 0.05), size: H * 0.045, weight: 0.55)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.04), size: H * 0.028)
            Draw.text(spec.tag, in: ctx, center: CGPoint(x: W * 0.86, y: H * 0.04), size: unit * 0.02,
                      color: Draw.rgb(1, 1, 1, 0.8))
        case .logo:
            let plate = CGRect(x: W * 0.04, y: H * 0.1, width: W * 0.92, height: H * 0.8)
            ctx.setFillColor(Draw.rgb(0.12, 0.14, 0.2, 0.9))
            ctx.addPath(CGPath(roundedRect: plate, cornerWidth: H * 0.18, cornerHeight: H * 0.18, transform: nil))
            ctx.fillPath()
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.56), size: H * 0.34, weight: 0.7)
            Draw.text(spec.subtitle, in: ctx, center: CGPoint(x: W / 2, y: H * 0.26), size: H * 0.1,
                      color: Draw.rgb(1, 1, 1, 0.75))
        }
        return ctx.makeImage()!
    }

    /// `image` scaled so its long edge is at most `longEdge` (unchanged when it already is).
    static func fitted(_ image: CGImage, longEdge: Int) -> CGImage {
        let long = max(image.width, image.height)
        guard long > longEdge else { return image }
        let scale = Double(longEdge) / Double(long)
        let w = Int((Double(image.width) * scale).rounded()), h = Int((Double(image.height) * scale).rounded())
        let ctx = Draw.context(w, h)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    /// Flattens alpha onto black — a JPEG cannot carry it, and an opaque still must not
    /// carry an alpha channel that says otherwise.
    static func opaque(_ image: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()!
    }

    enum Format: String {
        case png, jpeg, heic, webp
        var ext: String { self == .jpeg ? "jpg" : rawValue }
        var mime: String {
            switch self {
            case .png: "image/png"
            case .jpeg: "image/jpeg"
            case .heic: "image/heic"
            case .webp: "image/webp"
            }
        }
        /// The kit's codec vocabulary for stills (`MediaContentType.stillCodecName`).
        var codec: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            case .webp: "WebP"
            }
        }
    }

    /// Encodes `image` at `url`. No metadata is added: ImageIO writes the pixel facts only.
    static func write(_ image: CGImage, as format: Format, to url: URL, quality: Double = 0.82) throws {
        try? FileManager.default.removeItem(at: url)
        switch format {
        case .webp:
            let data = try WebPStillEncoder().encode(image, quality: quality)
            try data.write(to: url)
        case .png, .jpeg, .heic:
            let type: UTType = format == .png ? .png : (format == .jpeg ? .jpeg : .heic)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
            else { throw GenError.encode("no \(format) destination") }
            let options: [CFString: Any] = format == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, format == .jpeg ? opaque(image) : image, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw GenError.encode("\(format) finalize") }
        }
    }
}

// MARK: - Clips

enum ClipStyle {
    /// A countdown: seconds remaining large, the hue stepping each second (a cut on a
    /// second boundary is obvious), a progress bar along the bottom.
    case countdown
    /// A colour field with a bar sweeping across it.
    case loop
    /// A dark, quiet field for behind boards and branding, with a slow sweep.
    case backing
}

struct ClipSpec {
    let file: String
    let width: Int
    let height: Int
    let seconds: Int
    let style: ClipStyle
    let hue: Double
    let title: String       // e.g. "COUNTDOWN · H.264 · LANDSCAPE"
    let tag: String
    var fps: Int32 = 30
}

enum VideoCodec {
    case h264, hevc
    var type: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
    /// The kit's vocabulary (`MediaService.videoCodecName`).
    var name: String { self == .h264 ? "H.264" : "HEVC" }
}

enum Clips {
    /// Draws frame `index` of `spec` into `ctx` (y up, BGRA memory).
    static func drawFrame(_ index: Int, of spec: ClipSpec, in ctx: CGContext) {
        let W = CGFloat(spec.width), H = CGFloat(spec.height), unit = min(W, H)
        let t = Double(index) / Double(spec.fps)
        let second = Int(t)
        switch spec.style {
        case .countdown:
            let step = Double(second % 5) / 5
            ctx.setFillColor(Draw.hsb(spec.hue + step * 0.08, 0.5, 0.22 + 0.1 * step))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.setFillColor(Draw.rgb(0.2, 0.6, 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W * CGFloat(t / Double(spec.seconds)), height: max(12, H * 0.02)))
            Draw.text("\(spec.seconds - second)", in: ctx, center: CGPoint(x: W / 2, y: H * 0.56),
                      size: unit * 0.42, weight: 0.7)
        case .loop:
            ctx.setFillColor(Draw.hsb(spec.hue, 0.5, 0.55))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 4) / 4)
            ctx.setFillColor(Draw.hsb(spec.hue + 0.5, 0.45, 0.85, 0.8))
            ctx.fill(CGRect(x: W * phase - W * 0.05, y: H * 0.3, width: W * 0.1, height: H * 0.4))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.6), size: unit * 0.075, weight: 0.6)
        case .backing:
            ctx.setFillColor(Draw.hsb(spec.hue, 0.45, 0.2))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let phase = CGFloat(t.truncatingRemainder(dividingBy: Double(spec.seconds)) / Double(spec.seconds))
            ctx.setFillColor(Draw.hsb(spec.hue, 0.4, 0.32))
            ctx.fill(CGRect(x: 0, y: H * phase, width: W, height: H * 0.12))
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.14), size: unit * 0.035,
                      color: Draw.rgb(1, 1, 1, 0.6))
        }
        Barcode.draw(index, in: ctx, width: spec.width, height: spec.height)
        Draw.text(String(format: "frame %03d · %05.2f s", index, t), in: ctx,
                  center: CGPoint(x: W / 2, y: H * 0.26), size: unit * 0.05, color: Draw.rgb(1, 0.85, 0.3))
        if case .countdown = spec.style {
            Draw.text(spec.title, in: ctx, center: CGPoint(x: W / 2, y: H * 0.9), size: unit * 0.035)
        }
        Draw.text(spec.tag, in: ctx, center: CGPoint(x: W / 2, y: H * 0.05), size: unit * 0.022,
                  color: Draw.rgb(1, 1, 1, 0.65))
    }

    /// Encodes `spec` at `url` in `codec`, `width`×`height` (scaled from the spec's own size
    /// when they differ), at `bitRate`. One keyframe a second, so a trim seeks cleanly.
    static func write(_ spec: ClipSpec, codec: VideoCodec, bitRate: Int, to url: URL,
                      width: Int? = nil, height: Int? = nil) throws {
        try? FileManager.default.removeItem(at: url)
        let outW = width ?? spec.width, outH = height ?? spec.height
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.type,
            AVVideoWidthKey: outW,
            AVVideoHeightKey: outH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoMaxKeyFrameIntervalKey: Int(spec.fps),
                AVVideoExpectedSourceFrameRateKey: Int(spec.fps),
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outW,
            kCVPixelBufferHeightKey as String: outH,
        ])
        writer.add(input)
        // No metadata items: the container says nothing about where or by whom it was made.
        writer.metadata = []
        guard writer.startWriting() else { throw writer.error ?? GenError.encode("startWriting") }
        writer.startSession(atSourceTime: .zero)

        // Frames are drawn at the spec's size, then scaled into the output buffer when the
        // rendition is smaller, so every rendition shows the same frame at the same index.
        let scaled = outW != spec.width || outH != spec.height
        let source = scaled ? CGContext(data: nil, width: spec.width, height: spec.height, bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue) : nil
        let total = spec.seconds * Int(spec.fps)
        for index in 0..<total {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            guard let pool = adaptor.pixelBufferPool else { throw GenError.encode("no pixel buffer pool") }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                  let pixels = buffer else { throw GenError.encode("pixel buffer") }
            CVPixelBufferLockBaseAddress(pixels, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: outW, height: outH,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            if let source {
                drawFrame(index, of: spec, in: source)
                ctx.interpolationQuality = .high
                ctx.draw(source.makeImage()!, in: CGRect(x: 0, y: 0, width: outW, height: outH))
            } else {
                drawFrame(index, of: spec, in: ctx)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: spec.fps)) else {
                throw writer.error ?? GenError.encode("append frame \(index)")
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(total), timescale: spec.fps))
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? GenError.encode("finishWriting") }
    }
}

enum GenError: Error, CustomStringConvertible {
    case encode(String)
    case check(String)
    var description: String {
        switch self {
        case .encode(let s): "encode: \(s)"
        case .check(let s): "check failed: \(s)"
        }
    }
}
