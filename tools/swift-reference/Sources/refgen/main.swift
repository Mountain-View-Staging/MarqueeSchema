/*
******************************************************

  main.swift
  @copyright 2026 Dustin Nielson

  Cross-implementation test tool. Exercises the LIVE MarqueeDataKit
  migrator and record types, so the JS peer is checked against Swift's
  real behaviour rather than against a transcription of it.

    refgen create  <path>                        build a reference database via GRDB
    refgen inspect <path>                        open a database, decode every record
                                                 type, emit JSON for the JS harness
    refgen publish <path> <configId> <out> <ts>  publish a surface cartridge
    refgen publish-project <path> <out> <ts>     publish the project cartridge
    refgen read-cartridge <path>                 open a CARTRIDGE through the kit's
                                                 reader (openCartridge / cartridgeMeta /
                                                 mediaManifest), emit JSON

  `inspect` is the round-trip proof for an AUTHORING database: if GRDB opens
  a JS-authored file, applies no migrations, and decodes every record, the
  desktop app opens it too. It is not for cartridges: a v25 cartridge is the
  wire format, carries no `grdb_migrations`, and is never opened through the
  migrator — `read-cartridge` is its counterpart, proving the kit's v25
  reader path on a JS-written artifact.

  `publish` takes an explicit `generatedAt` (unix ms) so the JS peer can
  produce a comparable cartridge — otherwise the two differ by a timestamp
  and every diff is noise. It mutates the source via markPublished, so the
  equivalence harness gives each implementation its own copy.

******************************************************
*/
import Foundation
import GRDB
import MarqueeDataKit

struct Summary: Encodable {
    var migrationsApplied: [String]
    var migrationsRunOnOpen: [String]
    var projectName: String?
    var projectCode: String?
    var cloudUid: String?
    var timezone: String?
    var projectDays: Int
    var mediaFiles: Int
    var mediaItems: Int
    var playlists: Int
    var playlistEntries: Int
    var directives: Int
    var surfaceConfigs: Int
    var surfaceLocations: Int
    var scheduleEntries: Int
    var tags: Int
    var mediaFileNames: [String]
    var mediaItemNames: [String]
    var playlistNames: [String]
    // v13: the project's two arrays, decoded through the kit's records.
    var emergencyScreens: Int
    var emergencyScreenDirectives: Int
    var projectLinks: Int
    var emergencyScreenNames: [String]
    var projectLinkURIs: [String]
}

func appliedIdentifiers(_ path: String) throws -> [String] {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
        guard try db.tableExists("grdb_migrations") else { return [] }
        return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
    }
}

/// What `read-cartridge` prints: the kit's view of a delivered artifact.
struct CartridgeRead: Encodable {
    var tables: [String]
    var meta: CartridgeMeta?
    var isV25: Bool?
    var isProjectOnly: Bool?
    var manifest: [ManifestEntry]
}

let usage = """
usage: refgen create <path>
       refgen inspect <path>
       refgen publish <path> <configId> <out> <generatedAtMs>
       refgen publish-project <path> <out> <generatedAtMs>
       refgen read-cartridge <path>
"""
guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
let command = CommandLine.arguments[1]
let path = CommandLine.arguments[2]

// A refusal is an ANSWER here, not a crash: callers (the web's cartridge test, STD-09) read it from
// stderr. An error escaping top-level code traps instead (SIGTRAP), which writes a crash report on every
// run, and on a macOS beta raises a crash dialog under the responsible app's name. So: message, exit 1.
do {
switch command {
case "create":
    try? FileManager.default.removeItem(atPath: path)
    let store = try MarqueeStore(path: path)
    _ = try await store.createProject(
        cloudUid: "00000000-0000-0000-0000-000000000000",
        name: "Reference",
        now: 0)
    print("wrote \(path)")

case "inspect":
    guard FileManager.default.fileExists(atPath: path) else {
        FileHandle.standardError.write(Data("no such database: \(path)\n".utf8))
        exit(2)
    }

    // Identifiers BEFORE opening through MarqueeStore, which runs the migrator.
    let before = try appliedIdentifiers(path)

    // The real test: MarqueeStore.init runs Self.migrator.migrate(). If the JS
    // peer authored grdb_migrations correctly this applies nothing; if it did
    // not, GRDB re-runs v1-relational and throws "table project already exists".
    let store = try MarqueeStore(path: path)
    let after = try appliedIdentifiers(path)
    let ranOnOpen = after.filter { !before.contains($0) }

    let project = try await store.loadProject()
    let days = try await store.projectDays()
    let service = MediaService(
        store: store,
        mediaDirectory: URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Media", isDirectory: true))

    // Each of these decodes rows into the app's record types. A column the JS
    // peer got wrong — name, type, nullability — surfaces here as a decode error.
    // A published cartridge carries only the tables it uses (a surface cartridge
    // has no tags; project.db has no surfaces/playlists/directives/tags), so the
    // optional tables are decoded only when present — the decode check still runs
    // wherever a table exists, and a full authoring DB has them all.
    let existingTables: Set<String> = try await store.writer.read { db in
        Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'"))
    }
    let files = try await service.listFiles()
    let items = try await service.listItems(includeArchived: true)
    let playlists = existingTables.contains("playlist")
        ? try await store.playlists(includeArchived: true) : []
    let surfaces = existingTables.contains("surface_config")
        ? try await store.surfaceConfigs(includeArchived: true) : []
    let tags = existingTables.contains("tag") ? try await store.allTags() : []
    let emergencyScreens = existingTables.contains("emergency_screen") ? try await store.emergencyScreens() : []
    let emergencySwitches = existingTables.contains("emergency_screen_directive")
        ? try await store.emergencyScreenDirectives() : []
    let projectLinks = existingTables.contains("project_link") ? try await store.projectLinks() : []

    var entryCount = 0
    var directiveCount = 0
    for playlist in playlists {
        guard let id = playlist.id else { continue }
        let entries = try await store.entries(inPlaylist: id)
        entryCount += entries.count
        for entry in entries {
            guard let entryId = entry.id else { continue }
            directiveCount += try await store.directives(forEntry: entryId).count
        }
    }

    var locationCount = 0
    var scheduleCount = 0
    for surface in surfaces {
        guard let id = surface.id else { continue }
        locationCount += try await store.surfaceLocations(inConfig: id).count
        scheduleCount += try await store.scheduleEntries(inConfig: id).count
    }

    let summary = Summary(
        migrationsApplied: after,
        migrationsRunOnOpen: ranOnOpen,
        projectName: project?.name,
        projectCode: project?.projectCode,
        cloudUid: project?.cloudUid,
        timezone: project?.timezone,
        projectDays: days.count,
        mediaFiles: files.count,
        mediaItems: items.count,
        playlists: playlists.count,
        playlistEntries: entryCount,
        directives: directiveCount,
        surfaceConfigs: surfaces.count,
        surfaceLocations: locationCount,
        scheduleEntries: scheduleCount,
        tags: tags.count,
        mediaFileNames: files.map(\.sourceFileName).sorted(),
        mediaItemNames: items.map(\.name).sorted(),
        playlistNames: playlists.map(\.name).sorted(),
        emergencyScreens: emergencyScreens.count,
        emergencyScreenDirectives: emergencySwitches.count,
        projectLinks: projectLinks.count,
        emergencyScreenNames: emergencyScreens.map(\.name),
        projectLinkURIs: projectLinks.map(\.uri))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(summary), encoding: .utf8)!)

case "publish":
    guard CommandLine.arguments.count >= 6,
          let configId = Int64(CommandLine.arguments[3]),
          let generatedAt = Int64(CommandLine.arguments[5])
    else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
    let out = CommandLine.arguments[4]
    let store = try MarqueeStore(path: path)
    let result = try await store.publishCartridge(
        configId: configId,
        to: URL(fileURLWithPath: out),
        now: generatedAt)
    print("published \(result.surfaceId) rev \(result.publishedRevision) — \(result.mediaFileCount) file(s)")

case "publish-project":
    guard CommandLine.arguments.count >= 5,
          let generatedAt = Int64(CommandLine.arguments[4])
    else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
    let out = CommandLine.arguments[3]
    let store = try MarqueeStore(path: path)
    let result = try await store.publishProjectCartridge(
        to: URL(fileURLWithPath: out),
        now: generatedAt)
    print("published project cartridge — \(result.mediaFileCount) file(s)")

case "read-cartridge":
    guard FileManager.default.fileExists(atPath: path) else {
        FileHandle.standardError.write(Data("no such cartridge: \(path)\n".utf8))
        exit(2)
    }
    // The consumer path: no migrator, the meta row keyed on format_version, the
    // manifest as a device fetches it.
    let store = try MarqueeStore.openCartridge(at: path)
    let tables: [String] = try store.writer.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    }
    let meta = try await store.cartridgeMeta()
    let manifest = try await store.mediaManifest()
    let read = CartridgeRead(
        tables: tables, meta: meta, isV25: meta?.isV25, isProjectOnly: meta?.isProjectOnly, manifest: manifest)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(read), encoding: .utf8)!)

default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
} catch {
    FileHandle.standardError.write(Data("refgen: \(error)\n".utf8))
    exit(1)
}
