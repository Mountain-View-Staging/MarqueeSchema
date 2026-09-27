//
//  Lock.swift — `media.lock.json`: every file of a show (or of legacy/), its size and
//  SHA-256. The repository's scripts/verify.sh checks a checkout against it; `verify`
//  here checks the generator's output the same way.
//

import CryptoKit
import Foundation

struct LockEntry: Codable, Equatable {
    let name: String
    let size: Int64
    let sha256: String
}

struct LockFile: Codable, Equatable {
    let folder: String
    /// Which files the lock covers: "*" (every file in the folder, recursively) or a suffix
    /// such as ".db" (legacy/, whose README and expectations are written by hand).
    let scope: String
    let files: [LockEntry]
}

enum Lock {
    static let fileName = "media.lock.json"

    /// Every regular file under `folder`, relative, sorted — the lock itself and Finder
    /// noise excepted.
    static func entries(in folder: URL, scope: String = "*") throws -> [LockEntry] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return []
        }
        var out: [LockEntry] = []
        let base = folder.standardizedFileURL.path
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let name = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if name == fileName || url.lastPathComponent == ".DS_Store" { continue }
            if scope != "*" && !name.hasSuffix(scope) { continue }
            out.append(LockEntry(name: name, size: Int64(values.fileSize ?? 0), sha256: try sha256(url)))
        }
        return out.sorted { $0.name < $1.name }
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func write(folder: URL, label: String, scope: String = "*") throws -> LockFile {
        let lock = LockFile(folder: label, scope: scope, files: try entries(in: folder, scope: scope))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(lock)
        data.append(0x0A)
        try data.write(to: folder.appendingPathComponent(fileName))
        return lock
    }

    /// Differences between `folder` and its lock, in words. Empty when they agree.
    static func verify(folder: URL) throws -> [String] {
        let data = try Data(contentsOf: folder.appendingPathComponent(fileName))
        let lock = try JSONDecoder().decode(LockFile.self, from: data)
        let actual = Dictionary(uniqueKeysWithValues: try entries(in: folder, scope: lock.scope).map { ($0.name, $0) })
        let locked = Dictionary(uniqueKeysWithValues: lock.files.map { ($0.name, $0) })
        var problems: [String] = []
        for (name, entry) in locked.sorted(by: { $0.key < $1.key }) {
            guard let found = actual[name] else { problems.append("missing: \(name)"); continue }
            if found.size != entry.size { problems.append("size: \(name) is \(found.size), locked \(entry.size)") }
            else if found.sha256 != entry.sha256 { problems.append("hash: \(name) differs from the lock") }
        }
        for name in actual.keys.sorted() where locked[name] == nil { problems.append("not in the lock: \(name)") }
        return problems
    }
}
