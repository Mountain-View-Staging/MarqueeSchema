//
//  main.swift — test-shows: generate and verify the generic test shows.
//
//    test-shows build  <checkout>                  everything: every show, the style book, legacy/
//    test-shows build  <checkout> --show BRAND26   only the shows named (repeatable) — BRAND26 with
//                                                  the style book it imports; nothing else is touched
//    test-shows legacy <checkout>                  legacy/ alone (the shows untouched)
//    test-shows verify <checkout>                  the Swift checks (see Verify.swift)
//
//  `build` deletes and rewrites only what it owns: shows/RIG26, shows/EDIT26, shows/BRAND26,
//  brands/ and LICENSES/Inter-OFL-1.1.txt (with BRAND26), and the artifacts in legacy/ (with
//  a full build). Commit the result deliberately; a regeneration renames every media file of
//  the shows it builds (the kit mints the names) and re-encodes every clip.
//

import Foundation

setbuf(stdout, nil)
let usage = """
usage: test-shows build  <path to the marquee-test-shows checkout> [--show <CODE>]...
       test-shows legacy <path to the marquee-test-shows checkout>
       test-shows verify <path to the marquee-test-shows checkout>
"""
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail(usage) }
let command = arguments[1]
let repo = URL(fileURLWithPath: arguments[2]).standardizedFileURL
var only: [String] = []
var options = Array(arguments.dropFirst(3))
while !options.isEmpty {
    let flag = options.removeFirst()
    guard command == "build", flag == "--show", !options.isEmpty else { fail(usage) }
    only.append(options.removeFirst())
}

// Refuse anything that is not the test-shows checkout: this tool deletes folders.
let readme = (try? String(contentsOf: repo.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
guard readme.hasPrefix("# Marquee test shows"), !repo.path.contains("MarqueeProjects") else {
    fail("\(repo.path) is not a marquee-test-shows checkout")
}

func buildLegacy() throws {
    let legacy = repo.appendingPathComponent("legacy", isDirectory: true)
    for name in ["pre-v25-surface.db", "pre-v25-project.db", Lock.fileName] {
        try? FileManager.default.removeItem(at: legacy.appendingPathComponent(name))
    }
    let artifacts = try Legacy.build(into: legacy)
    let lock = try Lock.write(folder: legacy, label: "legacy", scope: ".db")
    print("legacy: \(artifacts.joined(separator: ", ")) — \(lock.files.count) files locked")
}

do {
    switch command {
    case "build":
        let all = [Rig26.code, Edit26.code, Brand26.code]
        if let unknown = only.first(where: { !all.contains($0) }) {
            fail("unknown show \(unknown) — the shows are \(all.joined(separator: ", "))")
        }
        let selected = only.isEmpty ? all : all.filter(only.contains)
        let shows = repo.appendingPathComponent("shows", isDirectory: true)
        try FileManager.default.createDirectory(at: shows, withIntermediateDirectories: true)
        for code in selected {
            try? FileManager.default.removeItem(at: shows.appendingPathComponent(code))
        }
        let started = Date()
        // The style book first: BRAND26 imports it.
        if selected.contains(Brand26.code) {
            for line in try ExampleStyle.build(repo: repo) { print(line) }
        }
        for code in selected {
            let report: ShowReport = switch code {
            case Rig26.code: try await Rig26.build(into: shows)
            case Edit26.code: try await Edit26.build(into: shows)
            default: try await Brand26.build(into: shows, styleBook: ExampleStyle.folder(in: repo))
            }
            let lock = try Lock.write(folder: shows.appendingPathComponent(report.code), label: "shows/\(report.code)")
            let bytes = lock.files.reduce(Int64(0)) { $0 + $1.size }
            print("\(report.code): \(lock.files.count) files, \(bytes) bytes")
            for line in report.lines { print("  " + line) }
        }
        if only.isEmpty { try buildLegacy() }
        print(String(format: "built in %.0f s", Date().timeIntervalSince(started)))
    case "legacy":
        try buildLegacy()
    case "verify":
        for line in try await Verify.run(repo: repo) { print(line) }
        print("verify: every check passed")
    default:
        fail(usage)
    }
} catch {
    FileHandle.standardError.write(Data("test-shows: \(error)\n".utf8))
    exit(1)
}
