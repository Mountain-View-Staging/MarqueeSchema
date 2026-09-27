//
//  Author.swift — builds one show through the kit's real write paths, on a fixed clock.
//
//  Every write goes through what Studio for Mac calls: ProjectFactory.create (the migrator),
//  MediaService.importFile (hash, dimensions, content type, codec, the `original` rendition),
//  MediaService.createMediaItem, the store's playlist, entry, window, playback-state,
//  directive, surface, location, schedule, session and wallpaper calls, and — for the
//  renditions the optimizer would make — MarqueeStore.upsertVariant plus a ledger row
//  (recordOptimization), exactly as Studio's MediaOptimizationQueue stores one. Only the
//  rendition BYTES come from this tool instead of the optimizer, and the ledger says so.
//
//  The clock is fixed: every write takes the next second after `start`. File names are
//  minted by the kit's importer (random UUIDs, as in Studio), so a regeneration renames
//  every file; `media.lock.json` records what was generated.
//

import CoreGraphics
import Foundation
import GRDB
import MarqueeDataKit

/// The ledger's engine string for everything this tool produces. Deliberately not Studio's
/// (`MediaOptimizationQueue.engines`): a row written by another engine settles nothing for
/// Studio's optimizer, which is the truth — these renditions were not made by it.
let generatorEngine = "marquee test-shows generator 1"

final class Author {
    let code: String
    let project: MarqueeProject
    var store: MarqueeStore { project.store }
    var service: MediaService { project.service }
    let staging: URL
    private(set) var clock: Int64
    /// Every media file imported, in order, with what was generated for it (for the report).
    private(set) var produced: [(file: MediaFile, renditions: [MediaFileVariant])] = []

    private init(code: String, project: MarqueeProject, staging: URL, clock: Int64) {
        self.code = code
        self.project = project
        self.staging = staging
        self.clock = clock
    }

    /// Creates `<showsDir>/<code>/` with the project row, the name and the venue zone.
    static func create(in showsDir: URL, code: String, name: String, cloudUid: String,
                       timezone: String, start: Int64) async throws -> Author {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-shows-\(code)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var clock = start
        let project = try await ProjectFactory.create(in: showsDir, code: code, name: name,
                                                      cloudUid: cloudUid, now: clock)
        clock += 1000
        var row = project.project
        row.timezone = timezone
        row.updated = clock
        try await project.store.updateProject(row)
        return Author(code: code, project: project, staging: staging, clock: clock)
    }

    /// The next write's timestamp.
    func now() -> Int64 {
        clock += 1000
        return clock
    }

    /// Moves the clock to `instant` (never backwards).
    func advance(to instant: Int64) {
        clock = max(clock, instant)
    }

    // MARK: - Days

    /// Whole venue-local days, as Studio's day editor writes them: 00:00:00.000 to 23:59:59.999.
    func setDays(_ isoDays: [String], zone: TimeZone) async throws -> [ProjectDay] {
        var out: [ProjectDay] = []
        for day in isoDays {
            let (start, end) = Venue.bounds(of: day, zone: zone)
            out.append(try await store.setProjectDay(day: day, startTime: start, endTime: end, now: now()))
        }
        return out
    }

    // MARK: - Media

    /// A rendition this tool makes for a still.
    enum StillRendition {
        case optimized            // HEIC, same pixels
        case web                  // JPEG (PNG when the still has alpha), long edge ≤ 1920
        case skipWeb(String)      // a web rendition not needed — recorded as such
    }

    /// A rendition this tool makes for a clip.
    enum ClipRendition {
        case optimized(bitRate: Int)            // HEVC
        case skipOptimized(String)              // no venue master — recorded as not needed
        case web(bitRate: Int)                  // H.264, ≤ 1080p
        case wifi(bitRate: Int)                 // HEVC, lower rate
    }

    /// Renders `spec`, writes it as `format`, imports it, and adds the renditions.
    @discardableResult
    func still(_ spec: StillSpec, as format: Stills.Format, quality: Double = 0.85,
               renditions: [StillRendition]) async throws -> MediaFile {
        // An opaque still carries no alpha channel: a reader that asks the header whether a
        // file has transparency (STD-10's rule does) must hear "no" from an opaque one.
        let rendered = Stills.render(spec)
        let image = spec.hasAlpha ? rendered : Stills.opaque(rendered)
        let source = staging.appendingPathComponent(spec.file)
        try Stills.write(image, as: format, to: source, quality: quality)
        return try await importStill(source, image: image, hasAlpha: spec.hasAlpha, renditions: renditions)
    }

    /// Imports a still that is already a file — `source`, whose pixels are `image` — and adds
    /// the renditions. BRAND26 imports its style book's assets this way, so the original in the
    /// show is the portal's file byte for byte.
    @discardableResult
    func importStill(_ source: URL, image: CGImage, hasAlpha: Bool,
                     renditions: [StillRendition]) async throws -> MediaFile {
        let stem = source.lastPathComponent
        let file = try await importOriginal(source)
        var made: [MediaFileVariant] = []
        for rendition in renditions {
            switch rendition {
            case .optimized:
                let url = staging.appendingPathComponent("opt-\(stem).heic")
                try Stills.write(image, as: .heic, to: url, quality: 0.72)
                made.append(try await addRendition(url, kind: .optimized, of: file, type: Stills.Format.heic.mime,
                                                   width: image.width, height: image.height, codec: "HEIC",
                                                   recipe: "generated → HEIC q0.72"))
            case .web:
                let small = Stills.fitted(image, longEdge: 1920)
                let format: Stills.Format = hasAlpha ? .png : .jpeg
                let url = staging.appendingPathComponent("web-\(stem).\(format.ext)")
                try Stills.write(small, as: format, to: url, quality: 0.8)
                made.append(try await addRendition(url, kind: .webOptimized, of: file, type: format.mime,
                                                   width: small.width, height: small.height, codec: format.codec,
                                                   recipe: "generated → \(format.codec) ≤1920 px"))
            case .skipWeb(let reason):
                try await ledger(file, .webOptimized, .notNeeded, reason: reason, recipe: nil)
            }
        }
        produced.append((file, made))
        return file
    }

    /// Encodes `spec` in `codec` at `bitRate`, imports it, and adds the renditions.
    @discardableResult
    func clip(_ spec: ClipSpec, codec: VideoCodec, bitRate: Int,
              renditions: [ClipRendition]) async throws -> MediaFile {
        let source = staging.appendingPathComponent(spec.file)
        try Clips.write(spec, codec: codec, bitRate: bitRate, to: source)
        let file = try await importOriginal(source)
        var made: [MediaFileVariant] = []
        for rendition in renditions {
            switch rendition {
            case .optimized(let rate):
                let url = staging.appendingPathComponent("opt-\(spec.file)")
                try Clips.write(spec, codec: .hevc, bitRate: rate, to: url)
                made.append(try await addRendition(url, kind: .optimized, of: file, type: "video/mp4",
                                                   width: spec.width, height: spec.height, codec: "HEVC",
                                                   recipe: "generated → HEVC \(rate / 1000) kb/s"))
            case .skipOptimized(let reason):
                try await ledger(file, .optimized, .notNeeded, reason: reason, recipe: nil)
            case .web(let rate):
                let (w, h) = Author.webSize(spec.width, spec.height)
                let url = staging.appendingPathComponent("web-\(spec.file)")
                try Clips.write(spec, codec: .h264, bitRate: rate, to: url, width: w, height: h)
                made.append(try await addRendition(url, kind: .webOptimized, of: file, type: "video/mp4",
                                                   width: w, height: h, codec: "H.264",
                                                   recipe: "generated → H.264 \(rate / 1000) kb/s ≤1080p"))
            case .wifi(let rate):
                let url = staging.appendingPathComponent("wifi-\(spec.file)")
                try Clips.write(spec, codec: .hevc, bitRate: rate, to: url)
                made.append(try await addRendition(url, kind: .wifiOptimized, of: file, type: "video/mp4",
                                                   width: spec.width, height: spec.height, codec: "HEVC",
                                                   recipe: "generated → HEVC \(rate / 1000) kb/s (wifi rung)"))
            }
        }
        produced.append((file, made))
        return file
    }

    /// The largest size with the same aspect whose SHORT edge is at most 1080 (even pixels).
    static func webSize(_ w: Int, _ h: Int) -> (Int, Int) {
        let short = min(w, h)
        guard short > 1080 else { return (w, h) }
        let scale = 1080.0 / Double(short)
        func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
        return (even(Double(w) * scale), even(Double(h) * scale))
    }

    /// Imports through `MediaService.importFile` — the one import path both platforms share.
    private func importOriginal(_ source: URL) async throws -> MediaFile {
        let result = try await service.importFile(at: source, now: now())
        guard !result.wasDeduplicated else {
            throw GenError.check("\(source.lastPathComponent) deduplicated against an earlier file — every generated file must be unique")
        }
        return result.mediaFile
    }

    /// Copies a produced rendition into the project root under a fresh name, hashing it in
    /// the same pass, and records it: `upsertVariant` plus the ledger — Studio's
    /// `MediaOptimizationQueue.store(_:as:…)` and `record(_:_:…)`, minus the optimizer.
    private func addRendition(_ produced: URL, kind: VariantKind, of file: MediaFile, type: String,
                              width: Int, height: Int, codec: String, recipe: String) async throws -> MediaFileVariant {
        guard let fileId = file.id else { throw GenError.check("file without id") }
        let name = "\(UUID().uuidString.lowercased()).\(produced.pathExtension)"
        let destination = service.mediaDirectory.appendingPathComponent(name)
        let hashed = try ContentHasher.hash(contentsOf: produced, copyingTo: destination)
        let stamp = now()
        let row = try await store.upsertVariant(MediaFileVariant(
            mediaFileId: fileId, kind: kind, fileName: name, contentType: type,
            width: width, height: height, fileSize: hashed.byteSize,
            contentHash: hashed.contentHash, codec: codec, created: stamp, updated: stamp))
        try await ledger(file, kind, .ready,
                         reason: "\(file.fileSize ?? 0) → \(hashed.byteSize) bytes (generated)", recipe: recipe)
        return row
    }

    private func ledger(_ file: MediaFile, _ kind: VariantKind, _ status: OptimizationStatus,
                        reason: String?, recipe: String?) async throws {
        guard let fileId = file.id else { return }
        let stamp = now()
        try await store.recordOptimization(MediaOptimization(
            mediaFileId: fileId, kind: kind, status: status, reason: reason, recipe: recipe,
            engine: generatorEngine, created: stamp, updated: stamp))
    }

    /// A media item over one or two files.
    @discardableResult
    func item(_ name: String, portrait: MediaFile? = nil, landscape: MediaFile? = nil,
              displayDuration: Double? = nil) async throws -> MediaItem {
        try await service.createMediaItem(name: name, portraitFileId: portrait?.id, landscapeFileId: landscape?.id,
                                          displayDuration: displayDuration, now: now())
    }

    // MARK: - Playlists

    func playlist(_ name: String) async throws -> Playlist {
        let stamp = now()
        return try await store.insertPlaylist(Playlist(name: name, created: stamp, updated: stamp))
    }

    @discardableResult
    func append(_ item: MediaItem, to playlist: Playlist) async throws -> PlaylistEntry {
        try await store.appendEntry(playlistId: playlist.id!, mediaItemId: item.id!, now: now())
    }

    /// Directives on one entry, each stamped at `now()`: (type, instant, on).
    func direct(_ entry: PlaylistEntry, _ rules: [(DirectiveType, Int64, Bool)], zone: String) async throws {
        let stamp = now()
        let directives = rules.map {
            Directive(entryId: entry.id!, type: $0.0, timestamp: $0.1, onScreen: $0.2, timezone: zone,
                      created: stamp, updated: stamp)
        }
        try await store.setDirectives(directives, forEntry: entry.id!, now: stamp)
    }

    // MARK: - Finish

    /// Checkpoints, closes, switches the authoring database to a rollback journal and
    /// vacuums it, so the committed file is one self-contained file with no WAL, no -shm
    /// and no free pages holding old rows. A Studio that opens a COPY puts it back in WAL.
    func finish() async throws {
        _ = try await store.checkpoint()
        try store.close()
        let path = project.root.appendingPathComponent(ProjectFactory.databaseSubpath).path
        try Author.compact(path)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        try? FileManager.default.removeItem(at: staging)
    }
}

// MARK: - Venue time

enum Venue {
    /// A venue-local calendar day's [00:00:00.000, 23:59:59.999] in unix ms.
    static func bounds(of isoDay: String, zone: TimeZone) -> (Int64, Int64) {
        let start = instant(isoDay, hour: 0, minute: 0, zone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let next = calendar.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: Double(start) / 1000))!
        return (start, Int64((next.timeIntervalSince1970 * 1000).rounded()) - 1)
    }

    /// A venue-local wall-clock instant in unix ms.
    static func instant(_ isoDay: String, hour: Int, minute: Int, second: Int = 0, zone: TimeZone) -> Int64 {
        let parts = isoDay.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                      hour: hour, minute: minute, second: second))!
        return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Unix ms of an ISO-8601 UTC instant ("2026-08-20T12:00:00Z").
    static func utc(_ iso: String) -> Int64 {
        let formatter = ISO8601DateFormatter()
        return Int64((formatter.date(from: iso)!.timeIntervalSince1970 * 1000).rounded())
    }
}

extension Author {
    /// Rollback journal + VACUUM on a closed database file: one self-contained file.
    static func compact(_ path: String) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "VACUUM")
        }
        try queue.close()
    }
}
