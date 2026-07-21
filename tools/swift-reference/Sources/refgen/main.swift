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
    refgen publish <path> <configId> <out> <ts>  publish a screen cartridge
    refgen publish-project <path> <out> <ts>     publish the project-only cartridge

  `inspect` is the round-trip proof: if GRDB opens a JS-authored file,
  applies no migrations, and decodes every record, the desktop app opens
  it too.

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
    var screenConfigs: Int
    var screenLocations: Int
    var scheduleEntries: Int
    var tags: Int
    var mediaFileNames: [String]
    var mediaItemNames: [String]
    var playlistNames: [String]
}

func appliedIdentifiers(_ path: String) throws -> [String] {
    let queue = try DatabaseQueue(path: path)
    return try queue.read { db in
        guard try db.tableExists("grdb_migrations") else { return [] }
        return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
    }
}

let usage = """
usage: refgen create <path>
       refgen inspect <path>
       refgen publish <path> <configId> <out> <generatedAtMs>
       refgen publish-project <path> <out> <generatedAtMs>
"""
guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
let command = CommandLine.arguments[1]
let path = CommandLine.arguments[2]

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
    let files = try await service.listFiles()
    let items = try await service.listItems(includeArchived: true)
    let playlists = try await store.playlists(includeArchived: true)
    let screens = try await store.screenConfigs(includeArchived: true)
    let tags = try await store.allTags()

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
    for screen in screens {
        guard let id = screen.id else { continue }
        locationCount += try await store.screenLocations(inConfig: id).count
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
        screenConfigs: screens.count,
        screenLocations: locationCount,
        scheduleEntries: scheduleCount,
        tags: tags.count,
        mediaFileNames: files.map(\.sourceFileName).sorted(),
        mediaItemNames: items.map(\.name).sorted(),
        playlistNames: playlists.map(\.name).sorted())

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
    print("published \(result.screenId) rev \(result.publishedRevision) — \(result.mediaFileCount) file(s)")

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

default:
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
