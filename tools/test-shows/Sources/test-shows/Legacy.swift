//
//  Legacy.swift — two synthetic pre-v25 artifacts, for the refusal tests.
//
//  Built the way the legacy publisher built its artifacts: the authoring schema as it stood
//  at `v2-media-variants` (the generated migrator, stopped there — `screen_*` tables and a
//  `grdb_migrations` table in the file), the tables a cartridge does not carry dropped, and
//  the pre-v25 `cartridge_meta` / `media_manifest` added with their old DDL. Generic rows only.
//
//    pre-v25-surface.db  a surface cartridge whose cartridge_meta has the OLD shape (no
//                        cartridge_kind, no format_version) → a Loader refuses it with
//                        `column_missing`
//    pre-v25-project.db  a project cartridge from before cartridge_meta existed → `not_v25`
//
//  No media bytes: a Loader refuses both before any file would be fetched.
//

import Foundation
import GRDB
import MarqueeDataKit

enum Legacy {
    /// `sql` without its `--` comments (the DDL has no string literal containing "--"),
    /// and without the blank lines they leave.
    static func uncommented(_ sql: String) -> String {
        sql.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let range = line.range(of: "--") else { return String(line) }
                return String(line[..<range.lowerBound]).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    static let stamp = Venue.utc("2025-09-01T12:00:00Z")
    static let zone = "America/New_York"

    /// The tables a pre-v25 cartridge carried, per artifact.
    static let surfaceTables: Set<String> = [
        "project", "project_days", "media_file", "media_file_variant", "media_item", "playlist", "playlist_entry",
        "directive", "screen_config", "screen_location", "screen_schedule_entry", "session", "session_set",
        "session_set_entry", "grdb_migrations", "sqlite_sequence",
    ]
    static let projectTables: Set<String> = [
        "project", "project_days", "media_file", "media_file_variant", "media_item", "grdb_migrations", "sqlite_sequence",
    ]

    static func build(into dir: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let surface = dir.appendingPathComponent("pre-v25-surface.db")
        let project = dir.appendingPathComponent("pre-v25-project.db")
        try write(surface, keep: surfaceTables, surfaceCartridge: true)
        try write(project, keep: projectTables, surfaceCartridge: false)
        return [surface.lastPathComponent, project.lastPathComponent]
    }

    private static func write(_ url: URL, keep: Set<String>, surfaceCartridge: Bool) throws {
        try? FileManager.default.removeItem(at: url)
        // The schema as the migrator left it at v2 — built in memory, then replayed into the
        // file statement by statement with the SQL comments taken out: the DDL is the old
        // shape, and the baseline's comments name internal design documents that have no
        // place in a public file.
        let template = try DatabaseQueue()
        try MarqueeSchema.migrator.migrate(template, upTo: "v2-media-variants")
        let (statements, identifiers) = try template.read { db -> ([String], [String]) in
            let ddl = try String.fetchAll(db, sql: """
                SELECT sql FROM sqlite_master
                WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'
                ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, rowid
                """)
            let ids = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            return (ddl, ids)
        }
        // Foreign keys off, as the migrator runs: the tables a cartridge does not carry are
        // dropped below in no particular order.
        var configuration = Configuration()
        configuration.foreignKeysEnabled = false
        let queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try queue.write { db in
            for statement in statements { try db.execute(sql: Legacy.uncommented(statement)) }
            for identifier in identifiers {
                try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [identifier])
            }
        }
        let t = stamp
        let dayStart = Venue.instant("2025-09-10", hour: 0, minute: 0, zone: TimeZone(identifier: zone)!)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO project (id, cloud_uid, name, created, updated, timezone, project_code)
                VALUES (1, '00000000-0000-4000-8000-000000000925', 'Legacy sample', ?, ?, ?, 'OLD25')
                """, arguments: [t, t, zone])
            try db.execute(sql: """
                INSERT INTO project_days (id, day, start_time, end_time, created, updated)
                VALUES (1, '2025-09-10', ?, ?, ?, ?)
                """, arguments: [dayStart, dayStart + 86_399_999, t, t])
            let files: [(Int, String, String, Int, Int, String, Double?, Int?)] = [
                (1, "legacy-still-landscape.png", "image/png", 1920, 1080, "landscape", nil, 48_000),
                (2, "legacy-clip-landscape.mp4", "video/mp4", 1920, 1080, "landscape", 10.0, nil),
            ]
            for f in files where surfaceCartridge {
                try db.execute(sql: """
                    INSERT INTO media_file (id, source_file_name, content_type, width, height, orientation,
                                            aspect_ratio, intrinsic_duration, file_size, created, updated)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [f.0, f.1, f.2, f.3, f.4, f.5, Double(f.3) / Double(f.4), f.6, f.7, t, t])
                try db.execute(sql: """
                    INSERT INTO media_item (id, name, landscape_file_id, created, updated) VALUES (?, ?, ?, ?, ?)
                    """, arguments: [f.0, f.0 == 1 ? "Legacy still" : "Legacy clip", f.0, t, t])
            }
            if surfaceCartridge {
                try db.execute(sql: "INSERT INTO playlist (id, name, created, updated) VALUES (1, 'Legacy rotation', ?, ?)",
                               arguments: [t, t])
                for (id, item) in [(1, 1), (2, 2)] {
                    try db.execute(sql: """
                        INSERT INTO playlist_entry (id, playlist_id, media_item_id, position, created, updated)
                        VALUES (?, 1, ?, ?, ?, ?)
                        """, arguments: [id, item, id - 1, t, t])
                    try db.execute(sql: """
                        INSERT INTO directive (id, entry_id, type, timestamp, on_screen, timezone, created, updated)
                        VALUES (?, ?, 'standard', ?, 1, ?, ?, ?)
                        """, arguments: [id, id, dayStart, zone, t, t])
                }
                try db.execute(sql: """
                    INSERT INTO screen_config (id, name, revision, created, updated, screen_id, published_revision, published_at)
                    VALUES (1, 'Legacy screen', 1, ?, ?, 'OLD1', 1, ?)
                    """, arguments: [t, t, t])
                try db.execute(sql: """
                    INSERT INTO screen_location (id, config_id, location_id, orientation, label, created, updated)
                    VALUES (1, 1, 'OLD1-A', 'landscape', 'Legacy sign', ?, ?)
                    """, arguments: [t, t])
                try db.execute(sql: """
                    INSERT INTO screen_schedule_entry (id, config_id, slot, timestamp, playlist_id, created, updated)
                    VALUES (1, 1, 'landscape', ?, 1, ?, ?)
                    """, arguments: [dayStart, t, t])
            }
            // Drop what a cartridge did not carry.
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            for table in tables where !keep.contains(table) {
                try db.execute(sql: "DROP TABLE \(table)")
            }
            // The pre-v25 manifest (no required hash, no required size), and — in a surface
            // cartridge only — the pre-v25 meta row, without cartridge_kind or format_version.
            try db.execute(sql: """
                CREATE TABLE media_manifest (
                  media_file_id INTEGER NOT NULL, deliverable_file_name TEXT NOT NULL,
                  content_hash TEXT, file_size INTEGER, content_type TEXT NOT NULL
                )
                """)
            for f in files where surfaceCartridge {
                try db.execute(sql: "INSERT INTO media_manifest VALUES (?, ?, NULL, ?, ?)",
                               arguments: [f.0, f.1, f.7, f.2])
            }
            if surfaceCartridge {
                try db.execute(sql: """
                    CREATE TABLE cartridge_meta (
                      screen_id TEXT, project_code TEXT, published_revision INTEGER NOT NULL,
                      show_wallpaper_item_id INTEGER, desktop_wallpaper_item_id INTEGER,
                      cloud_media_base_url TEXT, timezone TEXT,
                      generated_at INTEGER NOT NULL
                    )
                    """)
                try db.execute(sql: """
                    INSERT INTO cartridge_meta VALUES ('OLD1', 'OLD25', 1, NULL, NULL, 'https://media.example.net/library', ?, ?)
                    """, arguments: [zone, t])
            }
        }
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
            try db.execute(sql: "VACUUM")
        }
        try queue.close()
    }
}
