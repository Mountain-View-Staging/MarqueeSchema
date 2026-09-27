//
//  ExampleStyle.swift — the test brand: a generic style book, `example/example-2026/1`, written
//  into the public repository in the brand portal's layout (brand spec §7.2) — what a portal
//  would publish, so it doubles as a stand-in portal for import tests (plan D-r2-28, FIX-03).
//
//    brands/example/example-2026/1/
//      style.json                 format 1.1, written as the portal publishes it: JSON.stringify
//      fonts/apple/<face>.otf     Inter 4.1's own OTF source files, unmodified
//      fonts/web/<face>.woff2     Inter 4.1's own WOFF2 builds, unmodified
//      assets/…                   a backing in both orientations and a transparent mark, drawn here
//    brands/media.lock.json       every file of brands/, its size and SHA-256
//    LICENSES/Inter-OFL-1.1.txt   the release's LICENSE.txt, verbatim (the OFL travels with the faces)
//
//  The faces come from `Resources/Inter-4.1/` (see its SOURCE.md) and nowhere else; every file
//  is checked against the hash SOURCE.md records before it is copied. Nothing is downloaded.
//
//  The values a producer must MEASURE are measured (spec §9): each face's PostScript name
//  against its own `name` table, in both formats; `tabularFigures` from the ten digit advances
//  and the `tnum` feature; `lineHeight` from the faces' metrics; the contrast of both text
//  inks per row band over the backings supplied here. The build refuses a style book whose
//  measurements disagree with it, and `verify` measures it all again from the published files.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import MarqueeSessionBoard

enum ExampleStyle {
    static let company = "example"
    static let style = "example-2026"
    static let version = 1
    static let displayName = "Example 2026"
    static var address: String { "\(company)/\(style)/\(version)" }

    /// `brands/<company>/<style>/<version>/` — the spec's §7.2 folder.
    static func folder(in repo: URL) -> URL {
        repo.appendingPathComponent("brands/\(company)/\(style)/\(version)", isDirectory: true)
    }

    // MARK: - Typefaces

    static let family = "Inter"
    static let cssFamily = "Inter"
    /// The face table (spec §3.2): SemiBold has no italic, and says so.
    static let faces: [(upTo: Int, regular: String, italic: String?)] = [
        (449, "Inter-Regular", "Inter-Italic"),
        (649, "Inter-SemiBold", nil),
        (1000, "Inter-Bold", "Inter-BoldItalic"),
    ]
    /// A headline face used by name, not by weight: another family (Inter Display).
    static let display = "InterDisplay-Black"
    /// Every face, in the order the book lists its files: the table's, then the display face.
    /// Each file is named for the face it holds.
    static let faceNames = ["Inter-Regular", "Inter-Italic", "Inter-SemiBold", "Inter-Bold", "Inter-BoldItalic", "InterDisplay-Black"]
    static let appleFiles = faceNames.map { "fonts/apple/\($0).otf" }
    static let webFiles = faceNames.map { "fonts/web/\($0).woff2" }

    // MARK: - Colour (spec §4.1)

    /// The brand's own vocabulary. The primary is a brand colour and not a text colour: it is
    /// under 3:1 on white, like the real brands' primaries — that is why `text` is separate.
    static let palette: [(String, String)] = [
        ("primary", "#2E9BFF"), ("secondary", "#122B5C"), ("tertiary", "#FFB547"), ("quaternary", "#5E7188"),
    ]
    /// The legibility contract. `onDark` is deliberately NOT pure white, so a client that reads
    /// its own fallback instead of the declared value is visible; `mutedOnDark` is deliberately
    /// absent, so a client derives it (30 % toward `onLight`); `mutedOnLight` is stated.
    static let text: [(String, String)] = [
        ("onLight", "#0D1A30"), ("onDark", "#F7F9FC"), ("mutedOnLight", "#4F5B6E"),
    ]
    static func colour(_ key: String) -> String {
        (palette + text).first { $0.0 == key }!.1
    }

    static let licence: [(String, String)] = [
        ("holder", "Example Co"), ("agreement", "EXAMPLE-0001"), ("scope", "test signage, all platforms"),
    ]

    // MARK: - Assets (spec §5)

    struct Asset {
        let id: String
        let file: String
        let width: Int
        let height: Int
    }

    /// A backing authored at each board canvas (2160 × 3840 portrait, 3840 × 2160 landscape),
    /// and a transparent mark for the board's logo slot. All drawn here.
    static let assets: [Asset] = [
        Asset(id: "backing-portrait", file: "assets/backing-portrait.jpg", width: 2160, height: 3840),
        Asset(id: "backing-landscape", file: "assets/backing-landscape.jpg", width: 3840, height: 2160),
        Asset(id: "mark-white", file: "assets/mark-white.png", width: 800, height: 240),
    ]
    static var backings: [Asset] { assets.filter { $0.id.hasPrefix("backing-") } }

    // MARK: - Build

    struct Measured {
        let facts: [FaceFacts]
        let tabularFigures: String
        let naturalLineHeight: Double
        let lineHeight: Double
    }

    /// Writes `brands/`, `LICENSES/Inter-OFL-1.1.txt` and `brands/media.lock.json`. Returns the
    /// report: what was measured, and the contrast per band.
    static func build(repo: URL) throws -> [String] {
        let fm = FileManager.default
        try Resources.verify()
        let brands = repo.appendingPathComponent("brands", isDirectory: true)
        try? fm.removeItem(at: brands)
        let root = folder(in: repo)
        for sub in ["fonts/apple", "fonts/web", "assets"] {
            try fm.createDirectory(at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        for name in faceNames {
            try fm.copyItem(at: Resources.inter.appendingPathComponent("apple/\(name).otf"),
                            to: root.appendingPathComponent("fonts/apple/\(name).otf"))
            try fm.copyItem(at: Resources.inter.appendingPathComponent("web/\(name).woff2"),
                            to: root.appendingPathComponent("fonts/web/\(name).woff2"))
        }
        let licences = repo.appendingPathComponent("LICENSES", isDirectory: true)
        try fm.createDirectory(at: licences, withIntermediateDirectories: true)
        let licenceCopy = licences.appendingPathComponent("Inter-OFL-1.1.txt")
        try? fm.removeItem(at: licenceCopy)
        try fm.copyItem(at: Resources.inter.appendingPathComponent("LICENSE.txt"), to: licenceCopy)

        // ── measure the faces as published ──
        let measured = try measure(root)
        var lines = faceLines(measured)

        // ── the assets, drawn in the style's own faces and colours ──
        for name in faceNames.map({ "fonts/apple/\($0).otf" }) {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(root.appendingPathComponent(name) as CFURL, .process, &error) {
                throw GenError.check("\(name) did not register: \(error.map { "\($0.takeRetainedValue())" } ?? "?")")
            }
        }
        for asset in assets {
            let url = root.appendingPathComponent(asset.file)
            if asset.id == "mark-white" {
                try Stills.write(try drawMark(width: asset.width, height: asset.height), as: .png, to: url)
            } else {
                try Stills.write(drawBacking(width: asset.width, height: asset.height), as: .jpeg, to: url, quality: 0.9)
            }
            let (w, h) = try pixelSize(url)
            guard (w, h) == (asset.width, asset.height) else {
                throw GenError.check("\(asset.file) is \(w) × \(h), declared \(asset.width) × \(asset.height)")
            }
        }

        // ── contrast per row band over each backing (spec §4.3) ──
        for backing in backings {
            let verdict = try contrast(of: root.appendingPathComponent(backing.file))
            lines += verdict.lines(backing.file)
            if verdict.decision.needsScrim {
                throw GenError.check("\(backing.file) defeats both text inks — it needs a scrim; draw a darker plate")
            }
        }

        // ── the manifest, as the portal publishes it ──
        let json = book(tabularFigures: measured.tabularFigures, lineHeight: measured.lineHeight).stringified
        try Data(json.utf8).write(to: root.appendingPathComponent("style.json"))
        let lock = try Lock.write(folder: brands, label: "brands")
        lines.append("brands/: \(lock.files.count) files, \(lock.files.reduce(Int64(0)) { $0 + $1.size }) bytes")
        return lines
    }

    /// Every face file of the folder, both platforms, measured through CoreText and held to
    /// the book: the name each file carries (three readings) is the face it is named for, one
    /// `tabularFigures` and one natural line height for the family.
    static func measure(_ root: URL) throws -> Measured {
        var facts: [FaceFacts] = []
        var problems: [String] = []
        for (path, expected) in zip(appleFiles + webFiles, faceNames + faceNames) {
            let f = try Fonts.facts(of: root.appendingPathComponent(path), path: path)
            facts.append(f)
            if f.postScriptName != expected { problems.append("\(path): CoreText reads \(f.postScriptName), not \(expected)") }
            if f.cgPostScriptName != expected { problems.append("\(path): CGFont reads \(f.cgPostScriptName ?? "nothing"), not \(expected)") }
            if f.nameRecords.isEmpty || f.nameRecords.contains(where: { $0 != expected }) {
                problems.append("\(path): name ID 6 reads \(f.nameRecords), not \(expected)")
            }
        }
        let verdicts = Set(facts.map(\.tabularFigures))
        if verdicts.count != 1 { problems.append("the faces disagree about tabular figures: \(verdicts.sorted())") }
        let naturals = Set(facts.map(\.hheaLineHeight))
        if naturals.count != 1 { problems.append("the faces disagree about their natural line height: \(naturals.sorted())") }
        guard problems.isEmpty, let tabular = verdicts.first, let natural = naturals.max() else {
            throw GenError.check(problems.joined(separator: "; "))
        }
        return Measured(facts: facts, tabularFigures: tabular, naturalLineHeight: natural,
                        lineHeight: Fonts.declaredLineHeight(natural))
    }

    static func faceLines(_ m: Measured) -> [String] {
        var lines = ["style book \(address): \(m.facts.count) face files, PostScript names from each file's own name table (CoreText, CGFont, name ID 6):"]
        for f in m.facts {
            lines.append("  \(f.path): \(f.postScriptName) — \(f.format), weight \(f.weightClass)\(f.italic ? ", italic" : ""), "
                         + "digits \(f.distinctDigitWidths) distinct widths, tnum \(f.hasTnum ? "present" : "absent")"
                         + "\(f.tnumEqualizes ? String(format: " (all ten %.0f units)", f.tnumAdvances[0]) : ""), "
                         + "missing \(f.missing.isEmpty ? "none" : f.missing.joined(separator: " "))")
        }
        let r = m.facts[0]
        lines.append("  tabularFigures \"\(m.tabularFigures)\"; lineHeight \(m.lineHeight) — natural \(m.naturalLineHeight) em "
                     + "(hhea \(r.hhea.ascender)/\(r.hhea.descender)/\(r.hhea.lineGap) at \(r.unitsPerEm) upm; "
                     + "OS/2 typo \(r.typoLineHeight), win \(r.winLineHeight); CoreText \(r.coreTextLineHeight)), rounded up to 4 places")
        return lines
    }

    // MARK: - style.json

    /// The book, in the order spec §2.1 writes it.
    static func book(tabularFigures: String, lineHeight: Double) -> JSValue {
        .object([
            ("format", .string("1.1")),
            ("company", .string(company)),
            ("style", .string(style)),
            ("version", .number(Double(version))),
            ("displayName", .string(displayName)),
            ("fonts", .object([("family", .object([
                ("family", .string(family)),
                ("cssFamily", .string(cssFamily)),
                ("faces", .array(faces.map { face in
                    .object([("upTo", .number(Double(face.upTo))),
                             ("regular", .string(face.regular)),
                             ("italic", face.italic.map { .string($0) } ?? .null)])
                })),
                ("display", .string(display)),
                ("tabularFigures", .string(tabularFigures)),
                ("lineHeight", .number(lineHeight)),
                ("files", .object([("apple", .array(appleFiles.map { .string($0) })),
                                   ("web", .array(webFiles.map { .string($0) }))])),
            ]))])),
            ("colour", .object([
                ("palette", .object(palette.map { ($0.0, .string($0.1)) })),
                ("text", .object(text.map { ($0.0, .string($0.1)) })),
            ])),
            ("assets", .array(assets.map { a in
                .object([("id", .string(a.id)), ("kind", .string("image")), ("file", .string(a.file)),
                         ("width", .number(Double(a.width))), ("height", .number(Double(a.height)))])
            })),
            ("licence", .object(licence.map { ($0.0, .string($0.1)) })),
        ])
    }

    // MARK: - Drawing

    /// A navy plate, darkest under the room name and lifting toward the foot, with soft glows
    /// of the primary and the tertiary and a faint ring motif — dark everywhere text can sit.
    static func drawBacking(width: Int, height: Int) -> CGImage {
        let ctx = Draw.context(width, height)
        let W = CGFloat(width), H = CGFloat(height), long = max(W, H), unit = min(W, H)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // y is up: y = H is the top of the picture.
        let base = CGGradient(colorsSpace: space, colors: [Draw.hex("#163366"), Draw.hex("#08142C")] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        func glow(_ colour: String, _ alpha: CGFloat, at c: CGPoint, radius r: CGFloat) {
            let g = CGGradient(colorsSpace: space, colors: [Draw.hex(colour, alpha), Draw.hex(colour, 0)] as CFArray,
                               locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        let primary = colour("primary"), tertiary = colour("tertiary")
        glow(primary, 0.22, at: CGPoint(x: W * 0.92, y: H * 0.9), radius: long * 0.45)
        glow(primary, 0.14, at: CGPoint(x: W * 0.06, y: H * 0.08), radius: long * 0.5)
        glow(tertiary, 0.07, at: CGPoint(x: W * 0.55, y: H * 0.45), radius: long * 0.3)
        ctx.setStrokeColor(Draw.hex(colour("onDark"), 0.05))
        ctx.setLineWidth(unit * 0.004)
        for ring in 1...8 {
            let r = long * 0.06 * CGFloat(ring)
            ctx.strokeEllipse(in: CGRect(x: W * 0.92 - r, y: H * 0.9 - r, width: 2 * r, height: 2 * r))
        }
        return Stills.opaque(ctx.makeImage()!)
    }

    /// A roundel in the primary with an E, and the wordmark EXAMPLE, both in the display face,
    /// in `text.onDark` — for dark backings — with a tertiary rule under the word. Transparent.
    static func drawMark(width: Int, height: Int) throws -> CGImage {
        let ctx = Draw.context(width, height)
        let W = CGFloat(width), H = CGFloat(height)
        let ink = Draw.hex(colour("onDark"))
        let disc = CGRect(x: H * 0.08, y: H * 0.08, width: H * 0.84, height: H * 0.84)
        ctx.setFillColor(Draw.hex(colour("primary")))
        ctx.fillEllipse(in: disc)
        try Draw.text("E", in: ctx, center: CGPoint(x: disc.midX, y: disc.midY), size: disc.height * 0.62,
                      color: ink, face: display)
        let left = disc.maxX + H * 0.12, right = W - H * 0.08
        let size = 100 * (right - left) / Draw.width("EXAMPLE", face: display, size: 100)
        try Draw.text("EXAMPLE", in: ctx, center: CGPoint(x: (left + right) / 2, y: H * 0.58), size: size,
                      color: ink, face: display)
        ctx.setFillColor(Draw.hex(colour("tertiary")))
        ctx.fill(CGRect(x: left, y: H * 0.2, width: right - left, height: H * 0.06))
        return ctx.makeImage()!
    }

    static func pixelSize(_ url: URL) throws -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { throw GenError.check("\(url.lastPathComponent) has no pixel size") }
        return (w, h)
    }

    // MARK: - Contrast (spec §4.3)

    /// Both text inks over one backing: the luminance extremes of each horizontal band — five,
    /// one per row of the schedule board, across the whole frame, because a style book does
    /// not know where a client's text will sit (§6) — decoded 480 px wide and read pixel by
    /// pixel (the brand portal's sampler: an area comparable to a glyph, not a whole-frame
    /// mean), then the kit's one rule, `Contrast.inkDecision`, over the worst of them.
    struct Verdict {
        struct Band {
            let band: Int
            let min: Double
            let max: Double
        }

        let bands: [Band]
        let onLight: RGBA
        let onDark: RGBA
        let decision: Contrast.InkDecision

        func worst(_ ink: RGBA, _ band: Band) -> Double {
            let l = Contrast.luminance(r: ink.r, g: ink.g, b: ink.b)
            return min(Contrast.ratio(l, band.min), Contrast.ratio(l, band.max))
        }

        func lines(_ name: String) -> [String] {
            var out = ["contrast over \(name), per band, text.onLight \(ExampleStyle.colour("onLight")) / text.onDark \(ExampleStyle.colour("onDark")):"]
            for band in bands {
                out.append(String(format: "  band %d: luminance %.4f…%.4f — onLight %.2f:1, onDark %.2f:1",
                                  band.band + 1, band.min, band.max, worst(onLight, band), worst(onDark, band)))
            }
            out.append("  " + Contrast.variantSummary(isDark: decision.useDark, worstRatio: decision.worstRatio,
                                                      alternativeRatio: decision.alternativeRatio,
                                                      needsScrim: decision.needsScrim))
            return out
        }
    }

    static func contrast(of url: URL, bands count: Int = 5, decodeWidth: Int = 480) throws -> Verdict {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GenError.check("\(url.lastPathComponent) does not decode")
        }
        return contrast(of: image, bands: count, decodeWidth: decodeWidth)
    }

    static func contrast(of image: CGImage, bands count: Int = 5, decodeWidth: Int = 480) -> Verdict {
        let w = min(decodeWidth, image.width)
        let h = max(1, Int((Double(image.height) * Double(w) / Double(image.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Memory row 0 is the TOP of the picture, so band 0 is the top band.
        var bands = (0..<count).map { Verdict.Band(band: $0, min: .infinity, max: -.infinity) }
        let perBand = Double(h) / Double(count)
        for y in 0..<h {
            let b = min(count - 1, Int(Double(y) / perBand))
            var lo = bands[b].min, hi = bands[b].max
            for x in 0..<w {
                let i = (y * w + x) * 4
                let l = Contrast.luminance(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255,
                                           b: Double(pixels[i + 2]) / 255)
                lo = min(lo, l)
                hi = max(hi, l)
            }
            bands[b] = Verdict.Band(band: b, min: lo, max: hi)
        }
        let onLight = RGBA(hex: colour("onLight")), onDark = RGBA(hex: colour("onDark"))
        let extremes = (min: bands.map(\.min).min()!, max: bands.map(\.max).max()!)
        return Verdict(bands: bands, onLight: onLight, onDark: onDark,
                       decision: Contrast.inkDecision(light: onLight, dark: onDark, extremes: extremes))
    }
}

// MARK: - The faces' source

enum Resources {
    /// `tools/test-shows/Resources/Inter-4.1` — found from this source file, so the tool runs
    /// from any directory.
    static let inter = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Inter-4.1", isDirectory: true)

    /// `SOURCE.md`'s table: file → SHA-256.
    static func recorded() throws -> [String: String] {
        let text = try String(contentsOf: inter.appendingPathComponent("SOURCE.md"), encoding: .utf8)
        let row = try NSRegularExpression(pattern: #"^\| `([^`]+)` \| `([0-9a-f]{64})` \|$"#, options: .anchorsMatchLines)
        var out: [String: String] = [:]
        for m in row.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            out[String(text[Range(m.range(at: 1), in: text)!])] = String(text[Range(m.range(at: 2), in: text)!])
        }
        return out
    }

    /// Every file the style book takes is the one SOURCE.md records, byte for byte.
    static func verify() throws {
        let recorded = try recorded()
        let wanted = ["LICENSE.txt"] + ExampleStyle.faceNames.flatMap { ["apple/\($0).otf", "web/\($0).woff2"] }
        for name in wanted {
            guard let hash = recorded[name] else { throw GenError.check("SOURCE.md records no hash for \(name)") }
            let actual = try Lock.sha256(inter.appendingPathComponent(name))
            guard actual == hash else { throw GenError.check("Resources/Inter-4.1/\(name) is not the file SOURCE.md records") }
        }
    }
}

// MARK: - JSON as the portal writes it

/// A JSON value written exactly as JavaScript's `JSON.stringify(value)` writes it: no
/// whitespace, keys in insertion order, numbers in their shortest form. That is how the brand
/// portal publishes a version's `style.json` (micro-services `src/brand/publish.js`,
/// `stampVersion`), so the stand-in carries the bytes a real portal would serve.
indirect enum JSValue {
    case object([(String, JSValue)])
    case array([JSValue])
    case string(String)
    case number(Double)
    case null

    var stringified: String {
        switch self {
        case .object(let pairs): "{" + pairs.map { JSValue.quote($0.0) + ":" + $0.1.stringified }.joined(separator: ",") + "}"
        case .array(let items): "[" + items.map(\.stringified).joined(separator: ",") + "]"
        case .string(let s): JSValue.quote(s)
        case .number(let n): n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : "\(n)"
        case .null: "null"
        }
    }

    /// JSON.stringify's escaping: the quote, the backslash and the control characters.
    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }
}
