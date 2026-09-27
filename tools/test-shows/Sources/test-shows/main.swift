//
//  main.swift — test-shows: generate and verify the generic test shows.
//
//    test-shows build  <marquee-test-shows checkout>   regenerate shows/ and legacy/, write the locks
//    test-shows legacy <marquee-test-shows checkout>   regenerate legacy/ alone (the shows untouched)
//    test-shows verify <marquee-test-shows checkout>   the Swift checks (see Verify.swift)
//
//  `build` deletes and rewrites only what it owns: shows/RIG26, shows/EDIT26 and the
//  artifacts in legacy/. Commit the result deliberately; a regeneration renames every
//  media file (the kit mints the names) and re-encodes every clip.
//

import Foundation

setbuf(stdout, nil)
let usage = """
usage: test-shows build  <path to the marquee-test-shows checkout>
       test-shows legacy <path to the marquee-test-shows checkout>
       test-shows verify <path to the marquee-test-shows checkout>
"""
let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
let repo = URL(fileURLWithPath: arguments[2]).standardizedFileURL

// Refuse anything that is not the test-shows checkout: this tool deletes folders.
let readme = (try? String(contentsOf: repo.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
guard readme.hasPrefix("# Marquee test shows"), !repo.path.contains("MarqueeProjects") else {
    FileHandle.standardError.write(Data("\(repo.path) is not a marquee-test-shows checkout\n".utf8))
    exit(2)
}

do {
    switch arguments[1] {
    case "build":
        let shows = repo.appendingPathComponent("shows", isDirectory: true)
        let legacy = repo.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: shows, withIntermediateDirectories: true)
        for code in [Rig26.code, Edit26.code] {
            try? FileManager.default.removeItem(at: shows.appendingPathComponent(code))
        }
        for name in ["pre-v25-surface.db", "pre-v25-project.db", Lock.fileName] {
            try? FileManager.default.removeItem(at: legacy.appendingPathComponent(name))
        }
        let started = Date()
        for build in [Rig26.build, Edit26.build] {
            let report = try await build(shows)
            let lock = try Lock.write(folder: shows.appendingPathComponent(report.code), label: "shows/\(report.code)")
            let bytes = lock.files.reduce(Int64(0)) { $0 + $1.size }
            print("\(report.code): \(lock.files.count) files, \(bytes) bytes")
            for line in report.lines { print("  " + line) }
        }
        let artifacts = try Legacy.build(into: legacy)
        let lock = try Lock.write(folder: legacy, label: "legacy", scope: ".db")
        print("legacy: \(artifacts.joined(separator: ", ")) — \(lock.files.count) files locked")
        print(String(format: "built in %.0f s", Date().timeIntervalSince(started)))
    case "legacy":
        let legacy = repo.appendingPathComponent("legacy", isDirectory: true)
        for name in ["pre-v25-surface.db", "pre-v25-project.db", Lock.fileName] {
            try? FileManager.default.removeItem(at: legacy.appendingPathComponent(name))
        }
        let artifacts = try Legacy.build(into: legacy)
        let lock = try Lock.write(folder: legacy, label: "legacy", scope: ".db")
        print("legacy: \(artifacts.joined(separator: ", ")) — \(lock.files.count) files locked")
    case "verify":
        for line in try await Verify.run(repo: repo) { print(line) }
        print("verify: every check passed")
    default:
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("test-shows: \(error)\n".utf8))
    exit(1)
}
