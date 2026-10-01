//
//  ZipArchive.swift
//  Marquee Template Builder
//
//  A ZIP reader and writer for template packages (PRD 13 F-10, M4) — the subset every unzip
//  understands: local file headers, a central directory, method 8 (deflate, raw, from the
//  Compression framework) or 0 (stored), CRC-32, no encryption, no zip64 (a package is a few
//  megabytes). Deterministic: entries written in the order given, with a fixed timestamp, so
//  the same files make the same bytes — a round trip is byte-identical.
//
//  Foundation + Compression only; symlinked into Tests/StageTests.
//

import Foundation
import Compression

nonisolated enum ZipArchive {

    struct Entry: Equatable {
        let path: String
        let data: Data
    }

    enum Failure: Error, CustomStringConvertible {
        case notAZip
        case unsupported(String)
        case corrupt(String)
        var description: String {
            switch self {
            case .notAZip: return "not a zip file"
            case .unsupported(let what): return "unsupported zip feature: \(what)"
            case .corrupt(let what): return "the zip is corrupt: \(what)"
            }
        }
    }

    // MARK: - CRC-32

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { raw in
            for byte in raw { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFFFFFF
    }

    // MARK: - Deflate

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 64
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            compression_encode_buffer(destination, capacity, raw.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return written > 0 ? Data(bytes: destination, count: written) : nil
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            compression_decode_buffer(destination, size, raw.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written == size else { throw Failure.corrupt("an entry inflated to \(written) bytes, not \(size)") }
        return Data(bytes: destination, count: size)
    }

    // MARK: - Writing

    /// A fixed DOS date/time (2026-01-01 00:00): archives are compared by their entries, not their clocks.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = UInt16((2026 - 1980) << 9 | 1 << 5 | 1)

    static func write(entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            var method: UInt16 = 0
            var payload = entry.data
            if let deflated = deflate(entry.data), deflated.count < entry.data.count { method = 8; payload = deflated }
            let offset = UInt32(out.count)
            // local file header
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0x0800)); out.append(le16(method))
            out.append(le16(dosTime)); out.append(le16(dosDate)); out.append(le32(crc))
            out.append(le32(UInt32(payload.count))); out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count))); out.append(le16(0))
            out.append(name); out.append(payload)
            // central directory record
            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20)); central.append(le16(0x0800)); central.append(le16(method))
            central.append(le16(dosTime)); central.append(le16(dosDate)); central.append(le32(crc))
            central.append(le32(UInt32(payload.count))); central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset))
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(centralOffset)); out.append(le16(0))
        return out
    }

    // MARK: - Reading

    static func read(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw Failure.notAZip }
        // The end-of-central-directory record: the last one in the final 64 KB + 22 bytes.
        let tail = max(0, data.count - 65_557)
        var eocd = -1
        var i = data.count - 22
        while i >= tail {
            if le32At(data, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notAZip }
        let count = Int(le16At(data, eocd + 10))
        var offset = Int(le32At(data, eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, le32At(data, offset) == 0x02014b50 else { throw Failure.corrupt("central directory") }
            let method = le16At(data, offset + 10)
            let flags = le16At(data, offset + 8)
            let compressed = Int(le32At(data, offset + 20))
            let size = Int(le32At(data, offset + 24))
            let nameLength = Int(le16At(data, offset + 28))
            let extraLength = Int(le16At(data, offset + 30))
            let commentLength = Int(le16At(data, offset + 32))
            let local = Int(le32At(data, offset + 42))
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength
            guard (flags & 0x0001) == 0 else { throw Failure.unsupported("encryption") }
            guard method == 0 || method == 8 else { throw Failure.unsupported("compression method \(method)") }
            guard local + 30 <= data.count, le32At(data, local) == 0x04034b50 else { throw Failure.corrupt("a local header") }
            let localName = Int(le16At(data, local + 26)), localExtra = Int(le16At(data, local + 28))
            let start = local + 30 + localName + localExtra
            guard start + compressed <= data.count else { throw Failure.corrupt("an entry runs past the end") }
            let payload = data.subdata(in: start..<(start + compressed))
            if name.hasSuffix("/") { continue }   // a directory entry
            let bytes = method == 8 ? try inflate(payload, size: size) : payload
            let crc = le32At(data, local + 14)
            guard crc == 0 || crc32(bytes) == crc else { throw Failure.corrupt("\(name) fails its CRC") }
            entries.append(Entry(path: name, data: bytes))
        }
        return entries
    }

    // MARK: - Folders

    /// A folder's regular files as entries, package-relative, symlinks resolved, sorted by path.
    /// ⚠️ Enumerated by PATH (`enumerator(atPath:)` yields relative subpaths): the URL enumerator
    /// reports `/private/var/…` for a `/var/…` folder and `resolvingSymlinksInPath` keeps `/var`,
    /// so prefix matching fails under the temp folder (2026-10-01).
    static func entries(of folder: URL, excluding: Set<String> = []) throws -> [Entry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: folder.path) else { throw Failure.corrupt("cannot read \(folder.path)") }
        var out: [Entry] = []
        while let relative = enumerator.nextObject() as? String {
            if relative.hasPrefix(".") || relative.contains("/.") { continue }
            let url = folder.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                // A symlinked folder (the repo's engine/) is not entered by the enumerator: enter it by hand.
                let resolved = url.resolvingSymlinksInPath()
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    for child in try entries(of: resolved) { out.append(Entry(path: relative + "/" + child.path, data: child.data)) }
                } else if !excluding.contains(relative) {
                    out.append(Entry(path: relative, data: try Data(contentsOf: resolved)))
                }
                continue
            }
            guard values?.isRegularFile == true, !excluding.contains(relative) else { continue }
            out.append(Entry(path: relative, data: try Data(contentsOf: url)))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Writes entries into a folder (created), refusing paths that climb out.
    static func extract(_ entries: [Entry], into folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries {
            let parts = entry.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty, !parts.contains(".."), !parts.contains(where: { $0.isEmpty }) else { throw Failure.corrupt("entry path \(entry.path)") }
            let target = parts.reduce(folder) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: target, options: .atomic)
        }
    }

    // MARK: - Little-endian helpers

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }
    private static func le16At(_ d: Data, _ i: Int) -> UInt16 { UInt16(d[d.startIndex + i]) | UInt16(d[d.startIndex + i + 1]) << 8 }
    private static func le32At(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(d[d.startIndex + i]) | UInt32(d[d.startIndex + i + 1]) << 8 | UInt32(d[d.startIndex + i + 2]) << 16 | UInt32(d[d.startIndex + i + 3]) << 24
    }
}
