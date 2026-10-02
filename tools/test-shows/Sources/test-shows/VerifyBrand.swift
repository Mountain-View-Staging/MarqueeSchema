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
//  BRAND26 (since PRD 14 M5-6, schema v16: a show carries no style book):
//    - no font or JSON file in the project or in either cartridge's manifest;
//    - the two session sets (schedule, now-next) carry the style's backing and mark, byte
//      for byte the portal's assets;
//    - the templates carry the brand: the Show's package declares its family (Inter), a
//      complete text pair and its WOFF2 faces, and picks its light text over the delivered
//      backings, with no scrim.
//

import CoreGraphics
import Foundation
import MarqueeDataKit
import MarqueeSessionBoard
import MarqueeSessionBoardTemplate
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
        let items = try await store.mediaItems(includeArchived: true)
        let files = Dictionary(uniqueKeysWithValues: try await store.mediaFiles().compactMap { f in f.id.map { ($0, f) } })
        let sets = try await store.sessionSets()
        try store.close()

        // M5-6 (schema v16, spec §9): the show carries no style book — its brand is its templates'.
        let styleBookFiles = files.values.filter { $0.contentType.hasPrefix("font/") || $0.contentType == "application/json" }
        check(styleBookFiles.isEmpty, "BRAND26: \(styleBookFiles.count) font or JSON files in the project — a style book's")
        // The two layouts, dressed in the style's selected assets.
        func bytes(ofItem id: Int64?, _ slot: KeyPath<MarqueeDataKit.MediaItem, Int64?>) -> String? {
            guard let item = items.first(where: { $0.id == id }), let fileId = item[keyPath: slot], let file = files[fileId] else { return nil }
            // The ORIGINAL: a still with an optimized rendition is delivered as that rendition.
            return try? Lock.sha256(show.appendingPathComponent(file.sourceFileName))
        }
        func portal(_ id: String) -> String? {
            try? Lock.sha256(root.appendingPathComponent(ExampleStyle.assets.first { $0.id == id }!.file))
        }
        check(sets.count == 2, "BRAND26: two session sets of the room, got \(sets.count)")
        for set in sets {
            check(bytes(ofItem: set.backingItemId, \.portraitFileId) == portal("backing-portrait")
                  && bytes(ofItem: set.backingItemId, \.landscapeFileId) == portal("backing-landscape")
                  && bytes(ofItem: set.logoItemId, \.portraitFileId) == portal("mark-white")
                  && bytes(ofItem: set.logoItemId, \.landscapeFileId) == portal("mark-white"),
                  "BRAND26: set \(set.id ?? 0) is not dressed in the style's backing and mark")
        }

        // The cartridges, through the Loader.
        let snap = try CartridgeLoader.load(contentsOf: show.appendingPathComponent("\(Brand26.surface).db"))
        let styleBookLines = snap.manifest.values.filter { $0.contentType.hasPrefix("font/") || $0.contentType == "application/json" }
        check(styleBookLines.isEmpty, "\(Brand26.surface).db: \(styleBookLines.count) font or JSON files in the manifest — a style book's")
        let projectSnap = try CartridgeLoader.loadProject(contentsOf: show.appendingPathComponent(CartridgeNaming.projectCartridgeFileName))

        // The session board templates (spec §5.15): the Show's and set 2's own, two zips the
        // manifest names, on every lane; project.db keeps the settings and drops the pointer.
        let zips = snap.manifest.values.filter { $0.contentType == "application/zip" }
        check(zips.count == 2, "\(Brand26.surface).db: \(zips.count) template packages in the manifest, not 2")
        check(snap.warnings.isEmpty, "\(Brand26.surface).db loads with warnings: \(snap.warnings.map(\.message))")
        let setsById = snap.sessionSets.values.sorted { $0.id < $1.id }
        check(snap.project.templateItemId != nil && snap.project.templateSettings?.vars["sponsorName"] == "Example sponsor",
              "\(Brand26.surface).db: the Show's template \(snap.project.templateItemId.map(String.init) ?? "—"), settings \(String(describing: snap.project.templateSettings))")
        check(setsById.count == 2 && setsById[0].templateItemId == nil && setsById[1].templateItemId != nil
              && setsById[1].templateItemId != snap.project.templateItemId
              && setsById[1].templateSettings?.vars["sponsorName"] == "The second room's sponsor",
              "\(Brand26.surface).db: set 2's own template \(setsById.last?.templateItemId.map(String.init) ?? "—"), set 1 the Show's")
        let templateFiles = Set([snap.project.templateItemId, setsById.last?.templateItemId].compactMap { $0 }.compactMap { snap.mediaItems[$0]?.portraitFileId })
        for lane in [MarqueeSurfaceEngine.Orientation.portrait, .landscape] {
            check(templateFiles.isSubset(of: filesForLanes(snap, lanes: [lane])), "\(Brand26.surface).db: the \(lane) lane does not fetch both template packages")
        }
        // Q-M5-04: project.db carries the Show's template — the project-only clock is its clock layout.
        let projectTemplateFile = projectSnap.project.templateItemId
            .flatMap { projectSnap.mediaItems[$0] }.flatMap { $0.portraitFileId ?? $0.landscapeFileId }
        check(projectSnap.project.templateItemId == snap.project.templateItemId
              && projectSnap.project.templateSettings?.vars["sponsorName"] == "Example sponsor"
              && projectTemplateFile.map { projectSnap.manifest[$0]?.contentType == "application/zip" } == true,
              "project.db: the Show's template \(projectSnap.project.templateItemId.map(String.init) ?? "—"), its package \(projectTemplateFile.map(String.init) ?? "—") — the clock needs both")
        if let projectTemplateFile {
            for lane in [MarqueeSurfaceEngine.Orientation.portrait, .landscape] {
                check(filesForLanes(projectSnap, lanes: [lane]).contains(projectTemplateFile), "project.db: the \(lane) lane does not fetch the Show's template")
            }
        }
        lines.append("  templates: \(zips.count) packages (\(zips.map { "\($0.fileSize) B" }.joined(separator: ", "))), the Show's item \(snap.project.templateItemId ?? 0), set 2's item \(setsById.last?.templateItemId ?? 0), on both lanes")

        // The boards are templates, and the templates carry the brand: family, text pair and faces.
        do {
            // The boards are templates (spec §5.15; PRD 14 M5-5 retired the built-in layouts):
            // set 1 draws the Show's, in the template's own text pair weighed over the delivered
            // backing where the template's text falls, on each stage — what a Surface chooses.
            let store = TemplatePackageStore(root: FileManager.default.temporaryDirectory
                .appendingPathComponent("verify-brand-\(UUID().uuidString)", isDirectory: true))
            defer { try? FileManager.default.removeItem(at: store.root) }
            if let itemId = snap.project.templateItemId, let fileId = snap.mediaItems[itemId]?.portraitFileId,
               let line = snap.manifest[fileId],
               let package = try? store.package(zipAt: show.appendingPathComponent(line.deliverableFileName), contentHash: line.contentHash) {
                let brand = package.manifest.brand
                let pair = ["onLight", "onDark", "mutedOnLight", "mutedOnDark"]
                let faces = (try? fm.contentsOfDirectory(atPath: package.folder.appendingPathComponent("fonts").path)) ?? []
                check(brand?.cssFamily == ExampleStyle.family && pair.allSatisfy { validHex(brand?.text?[$0]) }
                      && faces.contains { $0.hasSuffix(".woff2") },
                      "\(package.label): the template carries no complete brand (\(String(describing: brand?.text)), \(faces.count) font files)")
                lines.append("  \(package.label): brand \(brand?.cssFamily ?? "—"), text pair \(pair.compactMap { brand?.text?[$0] }.joined(separator: " ")), "
                             + "\(faces.filter { $0.hasSuffix(".woff2") }.count) WOFF2 faces in the package")
                let slots: [(String, KeyPath<MarqueeDataKit.MediaItem, Int64?>, BoardCanvas)] =
                    [("portrait", \.portraitFileId, .portrait), ("landscape", \.landscapeFileId, .landscape)]
                for (slot, keyPath, canvas) in slots {
                    guard let set = sets.first, let item = items.first(where: { $0.id == set.backingItemId }),
                          let fileId = item[keyPath: keyPath], let file = files[fileId] else { continue }
                    let url = show.appendingPathComponent(file.deliverableFileName)
                    let region = TemplateTextRegion.region(manifest: package.manifestObject, variant: .both, canvas: canvas.size)
                    let extremes = Contrast.backingExtremes(url: url, region: region)
                    let choice = TemplateInk.choose(brand: package.manifest.brand,
                                                    backing: extremes.map { .measured(min: $0.min, max: $0.max) } ?? .unmeasurable)
                    check(extremes != nil && choice.ink == .onDark && !choice.decision.needsScrim,
                          "the \(slot) backing under \(package.label): \(choice.decision.summary)")
                    lines.append(String(format: "  the %@ backing as a Surface measures it under %@: %.4f…%.4f, %@",
                                        slot, package.label, extremes?.min ?? -1, extremes?.max ?? -1, choice.decision.summary))
                }
            } else {
                check(false, "\(Brand26.surface).db: the Show's template package could not be read from the show folder")
            }
        }
        return (lines, failures)
    }
}
