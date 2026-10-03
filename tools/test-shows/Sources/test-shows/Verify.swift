//
//  Verify.swift — the Swift half of the checks (the Node half is verify-web.mjs and the
//  public repository's scripts/load-cartridges.mjs):
//
//    - a COPY of each show's `_studio/Marquee.db` opens with the kit and migrates nothing
//      (it is at the kit's newest identifier, and not superseded);
//    - every cartridge loads in the Swift engine's Loader with no warning, and reads through
//      the kit's consumer path as v25;
//    - every file a manifest names and every rendition a cartridge offers is in the show
//      folder, at its size and hash;
//    - filesForLanes on PORT1 (the portrait sign's config) returns its portrait lane's files and not
//      one landscape-only file;
//    - on DEMO1 a host without the DemoStation mode fetches what it fetches from PORT1 (the same
//      Rotation; the demo's branding stays at the origin), and a DemoStation host every file;
//    - the pre-v25 artifacts are refused with their codes;
//    - every lock file matches its folder;
//    - the style book and BRAND26: brand spec §9's producer items measured again from the
//      published files, and the branded show read back through the kit (VerifyBrand.swift).
//

import Foundation
import GRDB
import MarqueeDataKit
import MarqueeSurfaceEngine
import MarqueeSurfaceEngineLoader

enum Verify {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func run(repo: URL) async throws -> [String] {
        var lines: [String] = []
        var failures: [String] = []
        func check(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { failures.append(what()) }
        }
        func scheduleEntries(_ n: Int) -> String { "\(n) entr\(n == 1 ? "y" : "ies")" }
        let shows = repo.appendingPathComponent("shows")
        let codes = try FileManager.default.contentsOfDirectory(atPath: shows.path)
            .filter { !$0.hasPrefix(".") }.sorted()
        for code in codes {
            let root = shows.appendingPathComponent(code)
            // Each surface's lanes — [portrait, landscape] without the DemoStation mode, then with
            // it — and its manifest, for the checks across cartridges below.
            var surfaceLanes: [String: (plain: [Set<Int64>], demo: [Set<Int64>], manifest: Set<Int64>)] = [:]
            // ── the authoring database, through the kit, on a copy ──
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("verify-\(code)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let copy = tmp.appendingPathComponent("Marquee.db")
            try FileManager.default.copyItem(at: root.appendingPathComponent(ProjectFactory.databaseSubpath), to: copy)
            // A copy keeps the source's mode, and scripts/lock.sh makes the source read-only.
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: copy.path)
            let probe = try DatabaseQueue(path: copy.path)
            let before = try await probe.read { db in
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            }
            let superseded = try await probe.read { db in try MarqueeSchema.migrator.hasBeenSuperseded(db) }
            try probe.close()
            let store = try MarqueeStore(path: copy.path)
            let after = try await store.writer.read { db in
                try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            }
            check(before == MarqueeSchema.knownIdentifiers, "\(code): the authoring db is at \(before.last ?? "—"), not \(MarqueeSchema.knownIdentifiers.last!)")
            check(after == before, "\(code): opening the copy ran \(after.count - before.count) migration(s)")
            check(!superseded, "\(code): the authoring db reads as superseded")
            let project = try await store.loadProject()
            let files = try await store.mediaFiles()
            let items = try await store.mediaItems(includeArchived: true)
            let playlists = try await store.playlists(includeArchived: true)
            let entries = try await store.allPlaylistEntries()
            let directives = try await store.allDirectives()
            let configs = try await store.surfaceConfigs(includeArchived: true)
            let locations = try await store.allSurfaceLocations()
            let sets = try await store.sessionSets()
            let sessions = try await store.sessions()
            let variants = try await store.variantsByFile().values.reduce(0) { $0 + $1.count }
            lines.append("\(code) — \(project?.name ?? "?"), \(project?.timezone ?? "?"), v\(after.count) (\(after.last ?? "—")): "
                         + "\(files.count) media files, \(variants) renditions (originals included), \(items.count) items, "
                         + "\(playlists.count) playlists, \(entries.count) entries, \(directives.count) directives, "
                         + "\(configs.count) surface configs, \(locations.count) locations, \(sets.count) session set(s), \(sessions.count) sessions")
            try store.close()

            // ── the cartridges, through both Swift readers ──
            let cartridges = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".db") }.sorted { ($0 == "project.db" ? "" : $0) < ($1 == "project.db" ? "" : $1) }
            for name in cartridges {
                let url = root.appendingPathComponent(name)
                let manifest: [Int64: MarqueeSurfaceEngine.ManifestEntry]
                let offered: [Int64: [MarqueeSurfaceEngine.MediaFileVariant]]
                let warnings: [LoadWarning]
                var laneLine = ""
                if name == CartridgeNaming.projectCartridgeFileName {
                    let snap = try CartridgeLoader.loadProject(contentsOf: url)
                    manifest = snap.manifest; offered = snap.variants; warnings = snap.warnings
                    check(snap.meta.cartridgeKind == .project, "\(code)/\(name): kind \(snap.meta.cartridgeKind)")
                    let p = filesForLanes(snap, lanes: [.portrait]), l = filesForLanes(snap, lanes: [.landscape])
                    laneLine = "portrait lane \(p.count), landscape lane \(l.count)"
                } else {
                    let snap = try CartridgeLoader.load(contentsOf: url)
                    manifest = snap.manifest; offered = snap.variants; warnings = snap.warnings
                    let p = filesForLanes(snap, lanes: [.portrait]), l = filesForLanes(snap, lanes: [.landscape])
                    let dp = filesForLanes(snap, lanes: [.portrait], demo: true)
                    let dl = filesForLanes(snap, lanes: [.landscape], demo: true)
                    let bytes = { (ids: Set<Int64>) in ids.reduce(Int64(0)) { $0 + (snap.manifest[$1]?.fileSize ?? 0) } }
                    let schedule: String = "schedule: " + scheduleEntries(snap.scheduleBySlot.playlist.count) + " on the playlist slot, "
                        + scheduleEntries(snap.scheduleBySlot.demoStation.count) + " on the demo_station slot"
                    let locationIds: String = snap.locations.map(\.locationId).joined(separator: ", ")
                    let directiveCount: Int = snap.directives.values.reduce(0) { $0 + $1.standard.count + $1.takeover.count }
                    laneLine = "portrait lane \(p.count) (\(bytes(p)) B), landscape lane \(l.count) (\(bytes(l)) B)"
                        + ", DemoStation host: portrait \(dp.count) / landscape \(dl.count)"
                        + "; \(schedule); \(snap.locations.count) location(s): \(locationIds); \(directiveCount) directives"
                    surfaceLanes[snap.surfaceConfig.surfaceId] = ([p, l], [dp, dl], Set(snap.manifest.keys))
                    // The portrait sign's config (RIG26's PORT1): a config has one schedule
                    // (D-r2-30), and a portrait device fetches its lane's files and nothing
                    // that only a landscape slot names — fetch by lane (D-r2-23).
                    if snap.surfaceConfig.surfaceId == "PORT1" {
                        check(snap.scheduleBySlot.demoStation.isEmpty, "\(code)/\(name): PORT1 schedules no demo")
                        var portraitSlot = Set<Int64>(), landscapeSlot = Set<Int64>()
                        for item in snap.mediaItems.values {
                            if let f = item.portraitFileId { portraitSlot.insert(f) }
                            if let f = item.landscapeFileId { landscapeSlot.insert(f) }
                        }
                        let landscapeOnly = landscapeSlot.subtracting(portraitSlot)
                        check(p.isDisjoint(with: landscapeOnly), "\(code)/\(name): the portrait lane fetches a landscape-only file")
                        check(p == Set(snap.manifest.keys).subtracting(landscapeOnly),
                              "\(code)/\(name): the portrait lane is not every file but the landscape-only ones")
                        check(l.count + p.count - p.intersection(l).count == snap.manifest.count,
                              "\(code)/\(name): the two lanes do not cover the manifest")
                        laneLine += "; a portrait device: \(p.count) of \(snap.manifest.count) files, \(landscapeOnly.count) landscape-only files stay at the origin"
                    }
                }
                check(warnings.isEmpty, "\(code)/\(name): \(warnings.count) Loader warning(s): \(warnings.map(\.message).joined(separator: "; "))")
                // The kit's consumer path, on a copy (openCartridge is read-write by design).
                let kitCopy = tmp.appendingPathComponent("kit-\(name)")
                try FileManager.default.copyItem(at: url, to: kitCopy)
                let kit = try MarqueeStore.openCartridge(at: kitCopy.path)
                let meta = try await kit.cartridgeMeta()
                let kitManifest = try await kit.mediaManifest()
                try kit.close()
                check(meta?.isV25 == true, "\(code)/\(name): the kit does not read it as v25")
                check(kitManifest.count == manifest.count, "\(code)/\(name): kit manifest \(kitManifest.count) vs Loader \(manifest.count)")
                // Every byte a device could be sent is here, at its size and hash.
                var named: [(String, Int64, String)] = manifest.values.map { ($0.deliverableFileName, $0.fileSize, $0.contentHash) }
                for list in offered.values { named += list.map { ($0.fileName, $0.fileSize, $0.contentHash) } }
                var missing: [String] = []
                for (file, size, hash) in Set(named.map { "\($0.0)|\($0.1)|\($0.2)" }).sorted().map({ $0.split(separator: "|").map(String.init) })
                    .map({ ($0[0], Int64($0[1])!, $0[2]) }) {
                    let at = root.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: at.path) else { missing.append("\(file) absent"); continue }
                    if !(try ContentHasher.verify(contentsOf: at, contentHash: hash, fileSize: size)) {
                        missing.append("\(file) does not match its hash or size")
                    }
                }
                check(missing.isEmpty, "\(code)/\(name): \(missing.joined(separator: "; "))")
                let renditions = offered.values.reduce(0) { $0 + $1.count }
                lines.append("  \(name): rev \(meta?.publishedRevision ?? -1), \(manifest.count) manifest files, \(renditions) renditions offered, "
                             + "\(warnings.count) warnings; \(laneLine)")
            }
            // DEMO1 is PORT1's Rotation plus the demo's backgrounds and overlays (cartridge spec §7.7):
            // an item used only as demo branding is in a lane only on a host that runs the mode.
            if let demo1 = surfaceLanes["DEMO1"], let port1 = surfaceLanes["PORT1"] {
                check(demo1.plain == port1.plain, "\(code)/DEMO1.db: without the DemoStation mode its lanes are not PORT1's (the same Rotation)")
                check(demo1.demo.allSatisfy { $0 == demo1.manifest }, "\(code)/DEMO1.db: a DemoStation host does not fetch every file")
                let branding = demo1.manifest.subtracting(demo1.plain[0].union(demo1.plain[1]))
                lines.append("  DEMO1.db: without the DemoStation mode, PORT1's lanes (\(demo1.plain[0].count) / \(demo1.plain[1].count)); "
                             + "the \(branding.count) files of the demo's branding only on a DemoStation host")
            }
            // The published index (PRD 15 F-10): exactly what the Worker would write over these cartridges.
            let indexText = (try? String(contentsOf: root.appendingPathComponent(PublishedIndex.fileName), encoding: .utf8)) ?? ""
            let (expectedIndex, listed) = try PublishedIndex.render(showFolder: root, projectCode: code)
            check(indexText == expectedIndex, "\(code): \(PublishedIndex.fileName) is not the index of its cartridges")
            lines.append("  \(PublishedIndex.fileName): \(listed.joined(separator: ", "))")
            let problems = try Lock.verify(folder: root)
            check(problems.isEmpty, "\(code): lock: \(problems.joined(separator: "; "))")
        }

        // ── the pre-v25 artifacts ──
        let legacy = repo.appendingPathComponent("legacy")
        for (name, project, expected) in [("pre-v25-surface.db", false, CartridgeError.Code.columnMissing),
                                          ("pre-v25-project.db", true, CartridgeError.Code.notV25)] {
            let url = legacy.appendingPathComponent(name)
            do {
                if project { _ = try CartridgeLoader.loadProject(contentsOf: url) } else { _ = try CartridgeLoader.load(contentsOf: url) }
                failures.append("legacy/\(name): loaded, expected \(expected.rawValue)")
            } catch let error as CartridgeError {
                check(error.code == expected, "legacy/\(name): refused with \(error.code.rawValue), expected \(expected.rawValue)")
                lines.append("legacy/\(name): refused — \(error.code.rawValue): \(error.message)")
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("verify-legacy-\(UUID().uuidString).db")
            try FileManager.default.copyItem(at: url, to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let kit = try MarqueeStore.openCartridge(at: tmp.path)
            let meta = try await kit.cartridgeMeta()
            try kit.close()
            check(meta?.isV25 != true, "legacy/\(name): the kit reads it as v25")
            lines.append("  the kit's reader: \(meta.map { "pre-v25 meta, screen code \($0.surfaceId ?? "—"), isV25 \($0.isV25)" } ?? "no meta row")")
        }
        let legacyProblems = try Lock.verify(folder: legacy)
        check(legacyProblems.isEmpty, "legacy: lock: \(legacyProblems.joined(separator: "; "))")

        // ── the style book and BRAND26 (VerifyBrand.swift) ──
        let brand = try await VerifyBrand.run(repo: repo)
        lines += brand.lines
        failures += brand.failures

        if !failures.isEmpty {
            throw Failure(description: (["VERIFY FAILED:"] + failures.map { "  ✗ " + $0 }).joined(separator: "\n"))
        }
        return lines
    }
}
