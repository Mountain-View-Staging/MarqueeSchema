//
//  Templates.swift — BRAND26's session board templates (PRD 14, spec §5.15): the Show's
//  template and set 2's own, each a package zipped here from the builder's default template
//  (the reference package the specification publishes as template/default) — deterministic,
//  through the board kit's ZipArchive and its `files` rule (MarqueeSessionBoardTemplate) — and
//  imported through MediaService.importFile as any media is: one application/zip file, one
//  media item, the pointer set with the store's setProjectTemplate / setSessionSetTemplate.
//
//  The second template is adapted from the first (basedOn), with its own id, name and one
//  CSS rule, so a test can tell the two apart on screen.
//

import Foundation
import MarqueeDataKit
import MarqueeSessionBoardTemplate

enum Templates {

    /// The builder's default template, the source of both packages.
    static var defaultFolder: URL {
        URL(fileURLWithPath: #filePath)                       // …/tools/test-shows/Sources/test-shows/Templates.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // …/tools/test-shows
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // the workspace root
            .appendingPathComponent("MarqueeStudio/Marquee Template Builder/TemplateEngine/templates/default", isDirectory: true)
    }

    struct Imported {
        let projectItem: MediaItem
        let setItem: MediaItem
        let projectSettings: String
        let setSettings: String
        let notes: [String]
    }

    static let projectSettings = #"{"vars":{"sponsorName":"Example sponsor"}}"#
    static let setSettings = #"{"vars":{"sponsorName":"The second room's sponsor"}}"#

    /// Builds both packages, imports them, and points the project and `set` at them.
    static func importTemplates(_ a: Author, overrideSet: SessionSet) async throws -> Imported {
        let folder = defaultFolder
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("template.json").path) else {
            throw GenError.check("the builder's default template is not at \(folder.path)")
        }
        let first = try package(from: folder, id: "example-board", displayName: "Example — board", version: 1, basedOn: nil, extraCSS: nil)
        let second = try package(from: folder, id: "example-board-two", displayName: "Example — the second board", version: 1,
                                 basedOn: ("example-board", 1),
                                 extraCSS: "\n/* The second template: the same board, a larger title, so a test can tell the two apart. */\n.board { --title-size: 5.2rem; }\n")
        let projectItem = try await importPackage(a, first, name: "Template — Example — board v1")
        let setItem = try await importPackage(a, second, name: "Template — Example — the second board v1")
        try await a.store.setProjectTemplate(itemId: projectItem.id, settings: projectSettings, now: a.now())
        try await a.store.setSessionSetTemplate(overrideSet.id!, itemId: setItem.id, settings: setSettings, now: a.now())
        return Imported(projectItem: projectItem, setItem: setItem, projectSettings: projectSettings, setSettings: setSettings,
                        notes: ["templates: \(first.fileName) (\(first.zip.count) bytes) as the Show's, item \(projectItem.id ?? 0); "
                                + "\(second.fileName) (\(second.zip.count) bytes) on set \(overrideSet.id ?? 0), item \(setItem.id ?? 0)"])
    }

    struct Export {
        let zip: Data
        let fileName: String
    }

    /// The package as the builder exports one (its `TemplatePackage.export`, without the
    /// previews): every file of the folder, `template.json` with the identity rewritten and
    /// its `files` block — SHA-256 of every editable file and every font — then the
    /// deterministic zip. The engine folder is a symlink in the builder's tree; `entries`
    /// enters it by hand.
    static func package(from folder: URL, id: String, displayName: String, version: Int, basedOn: (String, Int)?, extraCSS: String?) throws -> Export {
        var entries = try ZipArchive.entries(of: folder, excluding: ["preview.html", "preview.png"])
        guard let manifestEntry = entries.first(where: { $0.path == "template.json" }),
              var manifest = try JSONSerialization.jsonObject(with: manifestEntry.data) as? [String: Any] else {
            throw GenError.check("template.json is missing or not an object in \(folder.path)")
        }
        for required in ["engine/marquee-template.js", "engine/nunjucks.js"] where !entries.contains(where: { $0.path == required }) {
            throw GenError.check("\(required) is not in the template package")
        }
        if let extraCSS, let i = entries.firstIndex(where: { $0.path == "styles.css" }) {
            entries[i] = ZipArchive.Entry(path: "styles.css", data: entries[i].data + Data(extraCSS.utf8))
        }
        manifest["id"] = id
        manifest["displayName"] = displayName
        manifest["version"] = version
        if let basedOn { manifest["basedOn"] = ["id": basedOn.0, "version": basedOn.1] } else { manifest.removeValue(forKey: "basedOn") }
        manifest["files"] = TemplatePackage.hashes(entries: entries.filter { $0.path != "template.json" })
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) + Data("\n".utf8)
        entries.removeAll { $0.path == "template.json" }
        entries.append(ZipArchive.Entry(path: "template.json", data: manifestData))
        entries.sort { $0.path < $1.path }
        return Export(zip: try ZipArchive.write(entries: entries), fileName: "\(id)-v\(version).marqueetemplate.zip")
    }

    /// The zip as media: imported by MediaService (content type by its extension), one item in the portrait slot.
    static func importPackage(_ a: Author, _ export: Export, name: String) async throws -> MediaItem {
        let url = a.staging.appendingPathComponent(export.fileName)
        try export.zip.write(to: url)
        let result = try await a.service.importFile(at: url, now: a.now())
        guard result.mediaFile.contentType == MediaContentType.templatePackage.rawValue, !result.wasDeduplicated else {
            throw GenError.check("\(export.fileName) imported as \(result.mediaFile.contentType), deduplicated \(result.wasDeduplicated)")
        }
        return try await a.item(name, portrait: result.mediaFile)
    }
}
