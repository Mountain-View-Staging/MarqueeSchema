//
//  PublishedIndex.swift — `<CODE>/_published.json`, the published index (PRD 15 F-10,
//  2026-10-03). In production the Worker writes it beside a show's cartridges on every publish
//  (micro-services `src/studio/publishedIndex.js`); here it is written from the show's own
//  cartridges, so Surface Web's tests read what production serves.
//
//  The Worker's bytes: JSON.stringify of
//    { format: 1, projectCode, updatedAt,
//      cartridges: [{ fileName, kind, surfaceCode, publishedRevision, generatedAt, size, etag }] }
//  `project.db` first, then the surfaces by file name; no person named. `etag` is the MD5 R2
//  gives a single-part upload; `updatedAt` is the newest `generated_at`, so writing it again over
//  unchanged cartridges gives the same bytes.
//

import CryptoKit
import Foundation
import GRDB

enum PublishedIndex {
    static let fileName = "_published.json"

    struct Entry {
        let fileName: String
        let kind: String
        let surfaceCode: String?
        let publishedRevision: Int64
        let generatedAt: Int64
        let size: Int64
        let etag: String
    }

    /// Writes `<show folder>/_published.json` from the cartridges at the folder's root; returns
    /// the file names it lists.
    @discardableResult
    static func write(showFolder: URL, projectCode: String) throws -> [String] {
        let (text, names) = try render(showFolder: showFolder, projectCode: projectCode)
        try Data(text.utf8).write(to: showFolder.appendingPathComponent(fileName), options: .atomic)
        return names
    }

    /// The index of the cartridges at the folder's root, and the file names it lists.
    static func render(showFolder: URL, projectCode: String) throws -> (String, [String]) {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: showFolder.path).filter { $0.hasSuffix(".db") }
        var entries: [Entry] = []
        for name in names {
            let url = showFolder.appendingPathComponent(name)
            var configuration = Configuration()
            configuration.readonly = true
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            let row = try queue.read { db in
                try Row.fetchOne(db, sql: "SELECT cartridge_kind, surface_id, published_revision, generated_at FROM cartridge_meta")
            }
            try queue.close()
            guard let row else { throw Refusal("\(name) has no cartridge_meta row") }
            let kind: String = row["cartridge_kind"]
            let data = try Data(contentsOf: url)
            entries.append(Entry(
                fileName: name,
                kind: kind,
                surfaceCode: kind == "project" ? nil : (row["surface_id"] as String?) ?? String(name.dropLast(3)),
                publishedRevision: row["published_revision"],
                generatedAt: row["generated_at"],
                size: Int64(data.count),
                etag: Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()))
        }
        entries.sort { a, b in a.kind == b.kind ? a.fileName < b.fileName : a.kind == "project" }
        let updatedAt = entries.map(\.generatedAt).max() ?? 0
        return (json(projectCode: projectCode, updatedAt: updatedAt, entries: entries), entries.map(\.fileName))
    }

    /// JSON.stringify's bytes, key order fixed (never JSONEncoder: its order is per process).
    static func json(projectCode: String, updatedAt: Int64, entries: [Entry]) -> String {
        func string(_ value: String) -> String {
            var out = "\""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\u{00}"..."\u{1F}": out += String(format: "\\u%04x", scalar.value)
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out + "\""
        }
        let cartridges = entries.map { e in
            "{\"fileName\":\(string(e.fileName)),\"kind\":\(string(e.kind)),\"surfaceCode\":\(e.surfaceCode.map(string) ?? "null"),"
                + "\"publishedRevision\":\(e.publishedRevision),\"generatedAt\":\(e.generatedAt),\"size\":\(e.size),\"etag\":\(string(e.etag))}"
        }
        return "{\"format\":1,\"projectCode\":\(string(projectCode)),\"updatedAt\":\(updatedAt),\"cartridges\":[\(cartridges.joined(separator: ","))]}"
    }

    struct Refusal: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
