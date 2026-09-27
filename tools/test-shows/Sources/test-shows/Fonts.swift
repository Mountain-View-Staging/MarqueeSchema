//
//  Fonts.swift — what a font FILE says about itself, read through CoreText, and the branding
//  specification's measurements over it (brand spec §3.1, §3.4, §3.5, §3.6).
//
//  CoreText decodes WOFF2 as well as OTF, so one reader covers both platforms' files: the
//  web faces are held to the same checks as the Apple ones rather than trusted because they
//  came from the same release. (Python's fontTools cannot open WOFF2 here: no brotli.)
//
//  Every number is MEASURED from the file's own tables — `name`, `head`, `hhea`, `OS/2`,
//  `hmtx` through `cmap`, `GSUB` — and the ones a client acts on are measured a second way,
//  through CoreText's own layout: the PostScript name as `CTFontCopyPostScriptName` and as
//  `CGFont` (the kit's StyleBook read-back), the line height as ascent + descent + leading,
//  the `tnum` digits as CoreText shapes them with the feature on.
//

import CoreGraphics
import CoreText
import Foundation

struct FaceFacts {
    /// The path the style book declares, e.g. `fonts/web/Inter-Regular.woff2`.
    let path: String
    let format: String
    /// `CTFontCopyPostScriptName` — the name Apple resolves by.
    let postScriptName: String
    /// `CGFont.postScriptName` — the read-back the kit's `StyleBook.load` holds a manifest to.
    let cgPostScriptName: String?
    /// Every `name` record with name ID 6, decoded, whatever its platform.
    let nameRecords: [String]
    /// Name ID 16 (typographic family), else name ID 1.
    let family: String
    let weightClass: Int
    let italic: Bool
    let unitsPerEm: Int
    let hhea: (ascender: Int, descender: Int, lineGap: Int)
    let typo: (ascender: Int, descender: Int, lineGap: Int)
    let win: (ascent: Int, descent: Int)
    /// CoreText's own line: (ascent + descent + leading) / size.
    let coreTextLineHeight: Double
    /// `0`…`9` through `cmap` into `hmtx`, in font units — the nominal advances, unkerned.
    let digitAdvances: [Int]
    /// The feature tags the `GSUB` FeatureList carries.
    let gsubFeatures: Set<String>
    /// Each digit alone, shaped by CoreText with `tnum` on, in font units.
    let tnumAdvances: [Double]
    /// Board code points the `cmap` lacks, as `U+XXXX`.
    let missing: [String]

    var hheaLineHeight: Double { Double(hhea.ascender - hhea.descender + hhea.lineGap) / Double(unitsPerEm) }
    var typoLineHeight: Double { Double(typo.ascender - typo.descender + typo.lineGap) / Double(unitsPerEm) }
    var winLineHeight: Double { Double(win.ascent + win.descent) / Double(unitsPerEm) }
    var distinctDigitWidths: Int { Set(digitAdvances).count }
    var hasTnum: Bool { gsubFeatures.contains("tnum") }
    /// True when `tnum` is present AND CoreText shapes all ten digits to one advance with it on.
    var tnumEqualizes: Bool { hasTnum && Set(tnumAdvances.map { ($0 * 1000).rounded() }).count == 1 }

    /// Spec §3.4's value, measured: `native` when the ten digits already advance alike,
    /// `tnum` when the feature exists and actually makes them alike, `none` otherwise.
    var tabularFigures: String {
        if distinctDigitWidths == 1 { return "native" }
        return tnumEqualizes ? "tnum" : "none"
    }
}

enum Fonts {
    /// What a board sets (the brand portal's `BOARD_CODEPOINTS`, spec §3.5): the digits, the
    /// time punctuation, U+2007 FIGURE SPACE (absent from both real families), and a Latin
    /// sample — plus the dashes, the middle dot and the apostrophe the test sessions use.
    static let boardCharacters: [Character] = Array("0123456789:.-\u{2013} \u{2007}azAZéü") + ["\u{2014}", "\u{00B7}", "\u{2019}", "&", "Ü"]

    enum ReadError: Error, CustomStringConvertible {
        case unreadable(String)
        case noTable(String, String)
        var description: String {
            switch self {
            case .unreadable(let p): "\(p): CoreText could not read it as a font"
            case .noTable(let p, let t): "\(p): no '\(t)' table"
            }
        }
    }

    /// Reads `url` (declared as `path`) through CoreText.
    static func facts(of url: URL, path: String) throws -> FaceFacts {
        let data = try Data(contentsOf: url)
        guard let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else {
            throw ReadError.unreadable(path)
        }
        let probe = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let upm = Int(CTFontGetUnitsPerEm(probe))
        // At size = unitsPerEm a point is a font unit, so CoreText's advances read in units.
        let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(upm), nil)

        func table(_ tag: Int, _ name: String) throws -> Data {
            guard let t = CTFontCopyTable(font, CTFontTableTag(tag), []) else { throw ReadError.noTable(path, name) }
            return t as Data
        }
        let head = try table(kCTFontTableHead, "head")
        let hhea = try table(kCTFontTableHhea, "hhea")
        let os2 = try table(kCTFontTableOS2, "OS/2")
        let name = try table(kCTFontTableName, "name")
        let hmtx = try table(kCTFontTableHmtx, "hmtx")
        let gsub = CTFontCopyTable(font, CTFontTableTag(kCTFontTableGSUB), []).map { $0 as Data }

        let records = nameRecords(name)
        let psRecords = records.filter { $0.id == 6 }.map(\.text)
        let family = records.first { $0.id == 16 }?.text ?? records.first { $0.id == 1 }?.text ?? ""

        // Digits through cmap into hmtx — the nominal advance, which is what a producer measures.
        let digits = Array("0123456789".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: digits.count)
        CTFontGetGlyphsForCharacters(font, digits, &glyphs, digits.count)
        let metrics = Int(hhea.u16(34))
        let advances = glyphs.map { glyph -> Int in
            let index = min(Int(glyph), metrics - 1)
            return Int(hmtx.u16(index * 4))
        }

        // tnum, shaped: each digit ALONE (a line of ten would be kerned), with the feature on.
        let settings = [[kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1]] as CFArray
        let tnumDescriptor = CTFontDescriptorCreateCopyWithAttributes(
            descriptor, [kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        let tnumFont = CTFontCreateWithFontDescriptor(tnumDescriptor, CGFloat(upm), nil)
        let tnumAdvances = "0123456789".map { digit -> Double in
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: String(digit),
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): tnumFont]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }

        var missing: [String] = []
        for character in boardCharacters {
            let units = Array(String(character).utf16)
            var glyph = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, units, &glyph, units.count) || glyph.contains(0) {
                missing.append(character.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))
            }
        }

        let sized = CTFontCreateWithFontDescriptor(descriptor, 100, nil)
        let magic = data.prefix(4)
        let format = switch String(decoding: magic, as: UTF8.self) {
        case "OTTO": "OpenType (CFF)"
        case "wOF2": "WOFF2"
        case "wOFF": "WOFF"
        case "true": "TrueType"
        default: magic == Data([0, 1, 0, 0]) ? "TrueType" : "unknown"
        }
        let cgName = CGDataProvider(data: data as CFData).flatMap { CGFont($0) }?.postScriptName as String?

        return FaceFacts(
            path: path, format: format,
            postScriptName: CTFontCopyPostScriptName(font) as String,
            cgPostScriptName: cgName,
            nameRecords: psRecords, family: family,
            weightClass: Int(os2.u16(4)), italic: os2.u16(62) & 1 == 1,
            unitsPerEm: Int(head.u16(18)),
            hhea: (Int(hhea.i16(4)), Int(hhea.i16(6)), Int(hhea.i16(8))),
            typo: (Int(os2.i16(68)), Int(os2.i16(70)), Int(os2.i16(72))),
            win: (Int(os2.u16(74)), Int(os2.u16(76))),
            coreTextLineHeight: Double(CTFontGetAscent(sized) + CTFontGetDescent(sized) + CTFontGetLeading(sized)) / 100,
            digitAdvances: advances,
            gsubFeatures: gsub.map(featureTags) ?? [],
            tnumAdvances: tnumAdvances,
            missing: missing)
    }

    /// Every record of a `name` table: (name ID, decoded text). Platforms 0 and 3 are UTF-16BE,
    /// platform 1 is Mac Roman.
    static func nameRecords(_ name: Data) -> [(id: Int, text: String)] {
        let count = Int(name.u16(2)), storage = Int(name.u16(4))
        var out: [(Int, String)] = []
        for i in 0..<count {
            let at = 6 + i * 12
            let platform = name.u16(at), id = Int(name.u16(at + 6))
            let length = Int(name.u16(at + 8)), offset = Int(name.u16(at + 10))
            let start = name.startIndex + storage + offset
            guard start + length <= name.endIndex else { continue }
            let bytes = name[start..<(start + length)]
            let text: String? = platform == 1
                ? String(data: bytes, encoding: .macOSRoman)
                : String(data: bytes, encoding: .utf16BigEndian)
            if let text { out.append((id, text)) }
        }
        return out
    }

    /// The tags of a `GSUB` table's FeatureList.
    static func featureTags(_ gsub: Data) -> Set<String> {
        let list = Int(gsub.u16(6))
        let count = Int(gsub.u16(list))
        var tags = Set<String>()
        for i in 0..<count {
            let at = gsub.startIndex + list + 2 + i * 6
            tags.insert(String(decoding: gsub[at..<(at + 4)], as: UTF8.self))
        }
        return tags
    }

    /// The natural line height a family declares (spec §3.6): the faces' `hhea` metric, the one
    /// CoreText lays out by, ROUNDED UP to four places — so no client comparing it with the
    /// metric in floating point reads the declaration as below it and reports a compression
    /// the brand never asked for.
    static func declaredLineHeight(_ natural: Double) -> Double {
        // The epsilon keeps a metric already at four places (1.2820) from rounding up to the next.
        ((natural * 10_000) - 1e-6).rounded(.up) / 10_000
    }
}

// MARK: - Big-endian reads

extension Data {
    func u16(_ offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) << 8 | UInt16(self[i + 1])
    }

    func i16(_ offset: Int) -> Int16 { Int16(bitPattern: u16(offset)) }
}
