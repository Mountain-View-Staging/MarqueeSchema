//
//  VerifyBrand.swift — the style book and BRAND26 (FIX-03), checked from the PUBLISHED files.
//
//  The style book, `brands/example/example-2026/1/`, against brand spec §9's producer items,
//  each measured again rather than trusted from the build:
//    - §7.2 the folder holds `style.json` and exactly the files it declares; the identity
//      matches the folder's address; the bytes are the book the measurements give, written as
//      the portal publishes one (JSON.stringify);
//    - §3.1 every face file, OTF and WOFF2 alike, carries the PostScript name of the face it
//      is — by CoreText, by CGFont and in every `name` record with ID 6 — and each platform
//      delivers exactly the declared faces, no more;
//    - §3.2 the table ascends to 1000, every entry states `italic`, and each face's weight
//      class and italic flag sit in the band that names it;
//    - §3.3 `family` and `cssFamily`; §3.4 `tabularFigures` as measured; §3.5 the board's
//      characters present; §3.6 `lineHeight` at or above every face's natural metric;
//    - §3.7 the source OTFs under `apple`, and each web face the same face as its source;
//      every face and the licence byte for byte the release's (Resources/Inter-4.1/SOURCE.md);
//    - §4.1 `palette.primary`, both text inks, `#RRGGBB` throughout, each text colour at
//      3:1 in its own context (the derived `mutedOnDark` too); §4.3 both inks per row band
//      over each backing, and the scrim case named as such (a synthetic backing that
//      defeats both inks must be reported as needing a scrim);
//    - §5 every asset with an id, a kind, a file and the file's own pixel size.
//
//  BRAND26, against the kit's import and the player's route:
//    - the project's reference, the 13 brand members (12 faces + the manifest), each face
//      byte for byte the portal's; the delivered `style.json` is the portal's book with each
//      declared path renamed, serialized as JSONSerialization writes it — re-derived here;
//    - the two session sets (schedule, now-next) carry the style's backing and mark, byte
//      for byte the portal's assets; BRAND1.db carries every brand member and names the
//      style book; every lane fetches all of them; project.db keeps the address only;
//    - `BrandDelivery.register(manifest:locate:)` — what the Surface calls — registers the
//      Apple faces from the show folder cleanly and builds the brand the book declares; the
//      boards' own chooser picks the dark ink over the delivered backings, with no scrim.
//

import CoreGraphics
import Foundation
import MarqueeDataKit
import MarqueeSessionBoard
import MarqueeSurfaceEngine
import MarqueeSurfaceEngineLoader

enum VerifyBrand {
    static func hex(_ c: RGBA) -> String {
        String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    static func validHex(_ s: String?) -> Bool {
        s?.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil
    }

    static func luminance(_ c: RGBA) -> Double { Contrast.luminance(r: c.r, g: c.g, b: c.b) }

    @MainActor
    static func run(repo: URL) async throws -> (lines: [String], failures: [String]) {
        var lines: [String] = []
        var failures: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { failures.append(what()) }
        }
        let fm = FileManager.default
        let address = ExampleStyle.address
        let brands = repo.appendingPathComponent("brands", isDirectory: true)
        let root = ExampleStyle.folder(in: repo)
        guard fm.fileExists(atPath: root.appendingPathComponent("style.json").path) else {
            return ([], ["brands/: no style book at \(address)"])
        }

        // ── the style book ───────────────────────────────────────────────────
        let raw = try Data(contentsOf: root.appendingPathComponent("style.json"))
        guard let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return (lines, ["style.json is not a JSON object"])
        }
        let book = try JSONDecoder().decode(StyleBook.self, from: raw)   // the kit's reader
        let family = book.fonts?.family
        let apple = family?.files?["apple"] ?? [], web = family?.files?["web"] ?? []
        let assets = book.assets ?? []

        // §7.2 — the folder is the book's, and nothing else.
        let onDisk = Set(try Lock.entries(in: root).map(\.name))
        let declared = Set(["style.json"] + apple + web + assets.map(\.file))
        check(onDisk == declared, "style book: the folder holds \(onDisk.subtracting(declared).sorted()) undeclared, "
              + "lacks \(declared.subtracting(onDisk).sorted())")
        check(book.format == "1.1" && book.company == ExampleStyle.company && book.style == ExampleStyle.style
              && book.version == ExampleStyle.version && root.pathComponents.suffix(3) == [book.company, book.style, "\(book.version ?? -1)"],
              "style book: identity \(book.format ?? "—") \(book.company)/\(book.style)/\(book.version.map(String.init) ?? "—") at \(root.path)")

        // §3.1 / §3.4 / §3.6 — the faces, measured from the published files.
        var measured: ExampleStyle.Measured?
        do { measured = try ExampleStyle.measure(root) } catch { failures.append("style book faces: \(error)") }
        if let measured {
            let expected = ExampleStyle.book(tabularFigures: measured.tabularFigures, lineHeight: measured.lineHeight).stringified
            check(String(decoding: raw, as: UTF8.self) == expected,
                  "style.json is not the book the measurements give, as the portal writes it")
            let names = Set((family?.faces ?? []).flatMap { [$0.regular, $0.italic].compactMap { $0 } } + [family?.display].compactMap { $0 })
            for platform in ["apple", "web"] {
                let actual = measured.facts.filter { $0.path.hasPrefix("fonts/\(platform)/") }.map(\.postScriptName)
                check(Set(actual) == names && actual.count == names.count,
                      "\(platform): the files carry \(actual.sorted()); the book declares \(names.sorted())")
            }
            check(family?.tabularFigures == measured.tabularFigures,
                  "tabularFigures: declared \(family?.tabularFigures ?? "—"), measured \(measured.tabularFigures)")
            check(family?.lineHeight == measured.lineHeight
                  && measured.facts.allSatisfy { (family?.lineHeight ?? 0) >= $0.hheaLineHeight && abs($0.coreTextLineHeight - $0.hheaLineHeight) < 1e-9 },
                  "lineHeight: declared \(family?.lineHeight.map { "\($0)" } ?? "—"), natural \(measured.naturalLineHeight)")
            check(measured.facts.allSatisfy { $0.missing.isEmpty },
                  "§3.5: \(measured.facts.filter { !$0.missing.isEmpty }.map { "\($0.path) lacks \($0.missing)" })")
            // §3.2 — each face sits in the band that names it.
            var low = 1
            for face in family?.faces ?? [] {
                check(face.upTo >= low, "face table: upTo \(face.upTo) does not ascend")
                for (name, italic) in [(face.regular, false)] + (face.italic.map { [($0, true)] } ?? []) {
                    for f in measured.facts where f.postScriptName == name {
                        check((low...face.upTo).contains(f.weightClass) && f.italic == italic,
                              "\(f.path): weight \(f.weightClass)\(f.italic ? " italic" : "") is not in the band \(low)…\(face.upTo) that names it")
                    }
                }
                low = face.upTo + 1
            }
            check(family?.faces?.last?.upTo == 1000, "face table: the last entry stops at \(family?.faces?.last?.upTo ?? -1)")
            let rawFaces = ((json["fonts"] as? [String: Any])?["family"] as? [String: Any])?["faces"] as? [[String: Any]] ?? []
            check(!rawFaces.isEmpty && rawFaces.allSatisfy { $0.keys.contains("italic") }, "face table: an entry omits italic")
            // §3.7 — the web face is its source's face.
            for name in ExampleStyle.faceNames {
                guard let a = measured.facts.first(where: { $0.path == "fonts/apple/\(name).otf" }),
                      let w = measured.facts.first(where: { $0.path == "fonts/web/\(name).woff2" }) else { continue }
                check(a.postScriptName == w.postScriptName && a.family == w.family && a.weightClass == w.weightClass
                      && a.italic == w.italic && a.unitsPerEm == w.unitsPerEm && a.hhea == w.hhea
                      && a.digitAdvances == w.digitAdvances && a.tnumAdvances == w.tnumAdvances,
                      "\(name): the web face is not the same face as its source")
            }
            lines += ExampleStyle.faceLines(measured)
        }
        check(apple.allSatisfy { $0.hasPrefix("fonts/apple/") && $0.hasSuffix(".otf") } && apple.count == ExampleStyle.faceNames.count,
              "§3.7: the apple platform is not the source OTFs: \(apple)")
        check(!(family?.family ?? "").isEmpty && !(family?.cssFamily ?? "").isEmpty, "§3.3: family and cssFamily are not both declared")
        let recorded = try Resources.recorded()
        for path in apple + web {
            let rel = String(path.dropFirst("fonts/".count))
            check(try Lock.sha256(root.appendingPathComponent(path)) == recorded[rel], "\(path) is not the release's file")
        }
        let licence = repo.appendingPathComponent("LICENSES/Inter-OFL-1.1.txt")
        let licenceHash = fm.fileExists(atPath: licence.path) ? try Lock.sha256(licence) : nil
        check(licenceHash != nil && licenceHash == recorded["LICENSE.txt"],
              "LICENSES/Inter-OFL-1.1.txt is not the release's LICENSE.txt")

        // §4.1 — the palette and the text pair.
        let colour = json["colour"] as? [String: Any]
        let palette = colour?["palette"] as? [String: String] ?? [:]
        let text = colour?["text"] as? [String: String] ?? [:]
        check(validHex(palette["primary"]) && validHex(text["onLight"]) && validHex(text["onDark"]),
              "§4.1: primary, onLight and onDark are not all declared")
        check((Array(palette.values) + Array(text.values)).allSatisfy { validHex($0) }, "§4.1: a colour is not #RRGGBB")
        if let onLight = text["onLight"], let onDark = text["onDark"] {
            let light = RGBA(hex: onLight), dark = RGBA(hex: onDark)
            let mutedOnDark = dark.mixed(toward: light, amount: 0.3)
            var legibility: [String] = []
            for (slot, value, against) in [("onLight", light, 1.0), ("onDark", dark, 0.0),
                                            ("mutedOnLight", RGBA(hex: text["mutedOnLight"] ?? onLight), 1.0),
                                            ("mutedOnDark (derived)", mutedOnDark, 0.0)] {
                let ratio = Contrast.ratio(luminance(value), against)
                legibility.append(String(format: "%@ %@ %.2f:1 on %@", slot, hex(value), ratio, against == 1 ? "white" : "black"))
                check(ratio >= 3, "§4.1: text.\(slot) \(hex(value)) reads \(ratio):1 in its own context")
            }
            let primary = RGBA(hex: palette["primary"] ?? "#000000")
            lines.append("  colour: " + legibility.joined(separator: "; ")
                         + String(format: "; palette.primary %@ %.2f:1 on white (a brand colour, not a text colour)",
                                  hex(primary), Contrast.ratio(luminance(primary), 1)))
        }

        // §4.3 — both inks per row band over each backing, and the scrim case named.
        for backing in ExampleStyle.backings {
            let verdict = try ExampleStyle.contrast(of: root.appendingPathComponent(backing.file))
            check(!verdict.decision.needsScrim && verdict.decision.useDark && verdict.decision.worstRatio >= 3,
                  "§4.3: \(backing.file): \(verdict.lines(backing.file).last ?? "")")
            lines += verdict.lines(backing.file).map { "  " + $0 }
        }
        let ranged = Draw.context(1080, 1920)
        let full = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [Draw.rgb(0, 0, 0), Draw.rgb(1, 1, 1)] as CFArray,
                              locations: [0, 1])!
        ranged.drawLinearGradient(full, start: .zero, end: CGPoint(x: 1080, y: 0), options: [])
        let scrim = ExampleStyle.contrast(of: ranged.makeImage()!)
        check(scrim.decision.needsScrim && scrim.lines("x").last?.contains("needs a scrim") == true,
              "§4.3: a backing running black to white is not reported as needing a scrim")
        lines.append("  a synthetic backing running black to white across every band: " + (scrim.lines("x").last ?? "")
            .trimmingCharacters(in: .whitespaces))

        // §5 — the catalogue.
        for asset in assets {
            let size = try? ExampleStyle.pixelSize(root.appendingPathComponent(asset.file))
            check(!asset.id.isEmpty && ["image", "video"].contains(asset.kind) && size.map { ($0.0, $0.1) == (asset.width, asset.height) } == true,
                  "§5: \(asset.id) is \(size.map { "\($0.0) × \($0.1)" } ?? "unreadable"), declared \(asset.width ?? -1) × \(asset.height ?? -1)")
        }
        let brandLock = try Lock.verify(folder: brands)
        check(brandLock.isEmpty, "brands: lock: \(brandLock.joined(separator: "; "))")
        lines.insert("brands/\(ExampleStyle.company)/\(ExampleStyle.style)/\(ExampleStyle.version): \(apple.count) apple + \(web.count) web faces, "
                     + "\(assets.count) assets; tabularFigures \(family?.tabularFigures ?? "—"), lineHeight \(family?.lineHeight.map { "\($0)" } ?? "—")", at: 0)

        // ── BRAND26 ──────────────────────────────────────────────────────────
        let show = repo.appendingPathComponent("shows/\(Brand26.code)", isDirectory: true)
        guard fm.fileExists(atPath: show.path) else { return (lines, failures + ["no shows/\(Brand26.code)"]) }
        let tmp = fm.temporaryDirectory.appendingPathComponent("verify-brand-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent("Marquee.db")
        try fm.copyItem(at: show.appendingPathComponent(ProjectFactory.databaseSubpath), to: copy)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy.path)
        let store = try MarqueeStore(path: copy.path)
        let project = try await store.loadProject()
        let items = try await store.mediaItems(includeArchived: true)
        let files = Dictionary(uniqueKeysWithValues: try await store.mediaFiles().compactMap { f in f.id.map { ($0, f) } })
        let sets = try await store.sessionSets()
        try store.close()

        check(project?.brandStyle == address, "BRAND26: the project is branded \(project?.brandStyle ?? "—")")
        let members = items.filter { $0.brandMember == address }
        check(members.count == apple.count + web.count + 1 && members.allSatisfy { $0.systemGenerated && $0.landscapeFileId == nil },
              "BRAND26: \(members.count) brand members")
        let manifestItem = items.first { $0.id == project?.brandStyleItemId }
        let manifestFile = manifestItem?.portraitFileId.flatMap { files[$0] }
        check(manifestItem?.brandMember == address && manifestItem?.name == "Style book — \(address)"
              && manifestFile?.contentType == "application/json"
              && manifestFile?.originalFileName == "\(ExampleStyle.company)-\(ExampleStyle.style)-\(ExampleStyle.version).json",
              "BRAND26: the reference names no style book item")
        var delivered: [String: String] = [:]
        for path in apple + web {
            let base = (path as NSString).lastPathComponent
            let matches = members.filter { $0.name == base }
            guard matches.count == 1, let file = matches[0].portraitFileId.flatMap({ files[$0] }) else {
                failures.append("BRAND26: \(matches.count) items for \(path)"); continue
            }
            delivered[path] = file.deliverableFileName
            let same = try Lock.sha256(show.appendingPathComponent(file.deliverableFileName)) == Lock.sha256(root.appendingPathComponent(path))
            check(file.originalFileName == base && file.contentType == (base.hasSuffix(".otf") ? "font/otf" : "font/woff2") && same,
                  "BRAND26: \(path) is not delivered byte for byte as \(file.deliverableFileName)")
        }
        // The delivered book: the portal's, each declared path renamed, as JSONSerialization writes it.
        if let manifestFile {
            var fonts = json["fonts"] as? [String: Any] ?? [:]
            var fam = fonts["family"] as? [String: Any] ?? [:]
            var paths = fam["files"] as? [String: [String]] ?? [:]
            for (platform, list) in paths { paths[platform] = list.map { delivered[$0] ?? ($0 as NSString).lastPathComponent } }
            fam["files"] = paths; fonts["family"] = fam
            var rewritten = json
            rewritten["fonts"] = fonts
            let expected = try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let actual = try Data(contentsOf: show.appendingPathComponent(manifestFile.deliverableFileName))
            check(actual == expected, "BRAND26: the delivered style.json is not the portal's book with the delivered names")
            lines.append("BRAND26 — \(address): \(members.count) brand members; the delivered style.json (\(actual.count) B, "
                         + "\(manifestFile.deliverableFileName)) is the portal's book with each path renamed, as JSONSerialization writes it")
        }
        // The two layouts, dressed in the style's selected assets.
        func bytes(ofItem id: Int64?, _ slot: KeyPath<MarqueeDataKit.MediaItem, Int64?>) -> String? {
            guard let item = items.first(where: { $0.id == id }), let fileId = item[keyPath: slot], let file = files[fileId] else { return nil }
            // The ORIGINAL: a still with an optimized rendition is delivered as that rendition.
            return try? Lock.sha256(show.appendingPathComponent(file.sourceFileName))
        }
        func portal(_ id: String) -> String? {
            try? Lock.sha256(root.appendingPathComponent(ExampleStyle.assets.first { $0.id == id }!.file))
        }
        check(sets.map(\.renderModes).sorted() == ["[\"now-next\"]", "[\"schedule\"]"], "BRAND26: the sets render \(sets.map(\.renderModes))")
        for set in sets {
            check(set.brandStyle == nil && bytes(ofItem: set.backingItemId, \.portraitFileId) == portal("backing-portrait")
                  && bytes(ofItem: set.backingItemId, \.landscapeFileId) == portal("backing-landscape")
                  && bytes(ofItem: set.logoItemId, \.portraitFileId) == portal("mark-white")
                  && bytes(ofItem: set.logoItemId, \.landscapeFileId) == portal("mark-white"),
                  "BRAND26: set \(set.renderModes) is not dressed in the style's backing and mark")
        }

        // The cartridges, through the Loader.
        let snap = try CartridgeLoader.load(contentsOf: show.appendingPathComponent("\(Brand26.surface).db"))
        let brandFiles = Set(snap.mediaItems.values.filter { $0.brandMember == address }.compactMap(\.portraitFileId))
        check(snap.project.brandStyleItemId == manifestItem?.id && brandFiles.count == members.count
              && brandFiles.isSubset(of: Set(snap.manifest.keys)),
              "\(Brand26.surface).db: \(brandFiles.count) brand files, style book item \(snap.project.brandStyleItemId.map(String.init) ?? "—")")
        for lane in [MarqueeSurfaceEngine.Orientation.portrait, .landscape] {
            let wanted = filesForLanes(snap, lanes: [lane])
            check(brandFiles.isSubset(of: wanted), "\(Brand26.surface).db: the \(lane) lane does not fetch every brand file")
        }
        let projectSnap = try CartridgeLoader.loadProject(contentsOf: show.appendingPathComponent(CartridgeNaming.projectCartridgeFileName))
        check(projectSnap.project.brandStyle == address && projectSnap.project.brandStyleItemId == nil,
              "project.db: brand \(projectSnap.project.brandStyle ?? "—"), item \(projectSnap.project.brandStyleItemId.map(String.init) ?? "—")")

        // The player's route: the flat show folder is the media cache.
        if let manifestFile {
            let outcome = BrandDelivery.register(manifest: show.appendingPathComponent(manifestFile.deliverableFileName),
                                                 platform: "apple") { name in
                let url = show.appendingPathComponent(name)
                return fm.fileExists(atPath: url.path) ? url : nil
            }
            let report = outcome.report
            check(outcome.isClean && report?.registered.count == apple.count && report?.maskedBySystem.isEmpty == true
                  && report?.registeredFromFolder(styleRoot: show).count == ExampleStyle.faceNames.count,
                  "BrandDelivery: \(outcome.summary); \(outcome.notes.joined(separator: "; "))")
            let brand = outcome.brand
            let onLight = RGBA(hex: ExampleStyle.colour("onLight")), onDark = RGBA(hex: ExampleStyle.colour("onDark"))
            check(brand.fonts.name == ExampleStyle.family && brand.fonts.display == ExampleStyle.display
                  && brand.fonts.postScriptName(weight: 400, italic: false) == "Inter-Regular"
                  && brand.fonts.postScriptName(weight: 600, italic: true) == "Inter-SemiBold"
                  && brand.fonts.postScriptName(weight: 700, italic: true) == "Inter-BoldItalic"
                  && hex(brand.ink) == hex(onLight) && hex(brand.onDark) == hex(onDark)
                  && hex(brand.muted) == hex(onDark.mixed(toward: onLight, amount: 0.3))
                  && hex(brand.mutedOnLight) == ExampleStyle.colour("mutedOnLight")
                  && hex(brand.palette.primary) == ExampleStyle.colour("primary"),
                  "BrandDelivery: the brand is not the book's")
            lines.append("  BrandDelivery.register(manifest:locate:): \(outcome.summary); ink \(hex(brand.ink)), onDark \(hex(brand.onDark)), "
                         + "muted (derived) \(hex(brand.muted)), mutedOnLight \(hex(brand.mutedOnLight))")
            // The boards' own chooser, over the delivered backings as a Surface measures them:
            // each board where its text is, on its own stage (SB-05).
            let slots: [(String, KeyPath<MarqueeDataKit.MediaItem, Int64?>, BoardCanvas)] =
                [("portrait", \.portraitFileId, .portrait), ("landscape", \.landscapeFileId, .landscape)]
            for (slot, keyPath, canvas) in slots {
                guard let set = sets.first, let item = items.first(where: { $0.id == set.backingItemId }),
                      let fileId = item[keyPath: keyPath], let file = files[fileId] else { continue }
                let url = show.appendingPathComponent(file.deliverableFileName)
                let rows = Contrast.backingExtremes(url: url, region: Contrast.textRegion(.schedule, on: canvas))
                let column = Contrast.backingExtremes(url: url, region: Contrast.textRegion(.nowNext, on: canvas))
                let schedule = ScheduleLayoutStyle.choose(brand: brand, backing: rows.map { .measured(min: $0.min, max: $0.max) } ?? .unmeasurable)
                let nowNext = SignageLayoutStyle.choose(brand: brand, backing: column.map { .measured(min: $0.min, max: $0.max) } ?? .unmeasurable)
                check(rows != nil && column != nil && schedule.isDark && !schedule.needsScrim && nowNext.isDark && !nowNext.needsScrim,
                      "the \(slot) backing: schedule \(schedule.summary); now/next \(nowNext.summary)")
                lines.append(String(format: "  the %@ backing as a Surface measures it: schedule rows %.4f…%.4f, board %@; now/next column %.4f…%.4f, board %@",
                                    slot, rows?.min ?? -1, rows?.max ?? -1, schedule.summary,
                                    column?.min ?? -1, column?.max ?? -1, nowNext.summary))
            }
        }
        return (lines, failures)
    }
}
