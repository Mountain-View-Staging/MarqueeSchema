//
//  Brand26.swift — BRAND26, the branded show (plan D-r2-28, FIX-03).
//
//  Its brand is its session board templates' (PRD 14 M5-6: a show carries no style book; the
//  Template Builder imports a brand from the portal into a template). The style's backing and
//  mark are selected from the stand-in portal's catalogue (`brands/`, ExampleStyle.swift, spec
//  §5): imported as ordinary media, byte for byte the portal's files, with the renditions
//  Studio's optimizer would add.
//
//  The show is one room's session board in both layouts — a schedule set and a now/next set
//  over the same sessions, each with the style's backing and mark — on one surface, whose one
//  schedule a device plays in either orientation (plan D-r2-30), so a client draws it in the
//  style's faces and colours. A session starts on every
//  hour of both venue days and runs 45 minutes, so whenever a Surface opens the show (Day 1
//  at the venue's current time of day, spec §8.2) one is on now or about to be, and the
//  quarter hour before each start is the board's "nothing now, next at" state.
//

import CoreGraphics
import Foundation
import ImageIO
import MarqueeDataKit

enum Brand26 {
    static let code = "BRAND26"
    static let zoneName = "America/Los_Angeles"
    static let zone = TimeZone(identifier: zoneName)!
    static let days = ["2026-09-14", "2026-09-15"]
    /// Authoring starts a week before Day 1; everything is published the day before it.
    static let authoringStart = Venue.utc("2026-09-07T12:00:00Z")
    static let publishAt = Venue.utc("2026-09-13T12:00:00Z")
    static let surface = "BRAND1"
    static let location = "BRAND1-A"
    static let room = "Main hall"

    /// Titles of every length a board has to set — one line, two lines, an accent, a dash, an
    /// ampersand, a curly apostrophe — and the breaks, which have no presenters.
    static let titles: [(title: String, type: String, presenters: Int)] = [
        ("Opening remarks", "Keynote", 2),
        ("Designing signs people can read from across the hall", "Breakout", 2),
        ("Type at a distance: size, weight and spacing", "Workshop", 1),
        ("Café break", "Break", 0),
        ("Colour, contrast & the backing behind the text", "Breakout", 2),
        ("Hands-on workshop \u{2013} tabular figures in time columns", "Workshop", 1),
        ("Panel discussion", "Panel", 2),
        ("Über-long session titles and how a board wraps them onto a second line", "Breakout", 1),
        ("Lightning talks", "Breakout", 2),
        ("What the sign\u{2019}s owner needs to know", "Breakout", 1),
        ("Networking", "Break", 0),
        ("Closing notes", "Keynote", 1),
    ]

    static func build(into showsDir: URL, styleBook: URL) async throws -> ShowReport {
        let a = try await Author.create(in: showsDir, code: code, name: "Brand sample",
                                        cloudUid: "00000000-0000-4000-8000-000000000326",
                                        timezone: zoneName, start: authoringStart)
        var report = ShowReport(code: code)
        _ = try await a.setDays(days, zone: zone)

        // ── The style's backing and mark, selected from its catalogue (spec §5) ──
        func asset(_ id: String) -> URL {
            styleBook.appendingPathComponent(ExampleStyle.assets.first { $0.id == id }!.file)
        }
        func decode(_ url: URL) throws -> CGImage {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw GenError.check("\(url.lastPathComponent) does not decode")
            }
            return image
        }
        let full: [Author.StillRendition] = [.optimized, .web]
        let alphaSet: [Author.StillRendition] = [.optimized, .skipWeb("already web-ready (PNG with alpha)")]
        let backingP = try await a.importStill(asset("backing-portrait"), image: try decode(asset("backing-portrait")),
                                               hasAlpha: false, renditions: full)
        let backingL = try await a.importStill(asset("backing-landscape"), image: try decode(asset("backing-landscape")),
                                               hasAlpha: false, renditions: full)
        let markFile = try await a.importStill(asset("mark-white"), image: try decode(asset("mark-white")),
                                               hasAlpha: true, renditions: alphaSet)
        let backing = try await a.item("Example 2026 backing", portrait: backingP, landscape: backingL)
        let mark = try await a.item("Example 2026 mark", portrait: markFile, landscape: markFile)

        // ── One room: a session on every hour of both days, 45 minutes each ──
        var sessions: [(Session, Int64, Int64)] = []
        for (d, day) in days.enumerated() {
            for hour in 0..<24 {
                let spec = titles[(hour + d * 5) % titles.count]
                let label = "D\(d + 1)-\(String(format: "%02d", hour))"
                let companies = ["Example Company A", "Example Company B", "Example Company C", "Example Company D",
                                 "Example Company E", "Example Company F", "Example Company G", "Example Company H"]
                let presenters = (0..<spec.presenters).map { n in
                    let who = "\(label)\(n == 0 ? "A" : "B")"
                    return "{\"firstName\":\"Presenter\",\"lastName\":\"\(who)\",\"fullName\":\"Presenter \(who)\","
                        + "\"jobTitle\":\"Speaker\",\"companyName\":\"\(companies[(hour + n + d) % companies.count])\"}"
                }
                let attributes = "[{\"attributeId\":\"SessionType\",\"attribute\":\"Session Type\",\"value\":\"\(spec.type)\"},"
                    + "{\"attributeId\":\"Track\",\"attribute\":\"Track\",\"value\":\"\(hour % 2 == 0 ? "Track A" : "Track B")\"}]"
                let t = a.now()
                let session = try await a.store.insertSession(Session(
                    name: "\(spec.title) (\(label))",
                    abstract: "Placeholder abstract for a generated test session, day \(d + 1) at \(hour):00.",
                    presenters: "[" + presenters.joined(separator: ",") + "]", attributes: attributes,
                    created: t, updated: t))
                sessions.append((session, Venue.instant(day, hour: hour, minute: 0, zone: zone),
                                 Venue.instant(day, hour: hour, minute: 45, zone: zone)))
            }
        }

        // ── The board in both layouts: two sets over the same sessions ──────
        // Two sets of the same room (a device chooses the layout — its board variant, spec §5.15 —
        // so the two sets no longer differ by mode; they stay two so the playlist has two boards).
        // The header is the set's name, so both read the room's.
        var sets: [SessionSet] = []
        for _ in ["first", "second"] {
            let stamp = a.now()
            let set = try await a.store.insertSessionSet(SessionSet(
                name: room, duration: 8,
                backingItemId: backing.id, logoItemId: mark.id, created: stamp, updated: stamp))
            for (session, start, end) in sessions {
                let t = a.now()
                _ = try await a.store.insertSessionSetEntry(SessionSetEntry(
                    sessionSetId: set.id!, sessionId: session.id!, startTime: start, endTime: end,
                    roomName: room, created: t, updated: t))
            }
            sets.append(set)
        }

        // ── The session board templates (spec §5.15): the Show's, and the second set's own ──
        let templates = try await Templates.importTemplates(a, overrideSet: sets[1])
        report.lines.append(contentsOf: templates.notes)

        // ── The playlist: both boards, on from the start of each venue day ──
        let boards = try await a.playlist("Boards")
        let daily: [(DirectiveType, Int64, Bool)] = days.map {
            (.standard, Venue.instant($0, hour: 0, minute: 0, zone: zone), true)
        }
        for set in sets {
            let entry = try await a.store.appendSessionSet(playlistId: boards.id!, sessionSetId: set.id!, now: a.now())
            try await a.direct(entry, daily, zone: zoneName)
        }

        // ── One surface: one schedule, played in either orientation ─────────
        let t = a.now()
        let config = try await a.store.insertSurfaceConfig(SurfaceConfig(surfaceId: surface, name: "Branded boards",
                                                                         created: t, updated: t))
        let lt = a.now()
        _ = try await a.store.insertSurfaceLocation(SurfaceLocation(configId: config.id!, locationId: location,
                                                                    label: "Branded sign", created: lt, updated: lt))
        let authored = a.clock
        try await a.store.schedulePlaylist(configId: config.id!, playlistId: boards.id!, timestamp: authored, now: a.now())

        // ── Publish: project.db, then the surface ────────────────────────────
        a.advance(to: publishAt)
        let root = a.project.root
        let projectResult = try await a.store.publishProjectCartridge(
            to: root.appendingPathComponent(CartridgeNaming.projectCartridgeFileName), now: a.now())
        report.lines.append("project.db rev \(projectResult.publishedRevision) — \(projectResult.mediaFileCount) file(s)")
        let result = try await a.store.publishCartridge(
            configId: config.id!,
            to: root.appendingPathComponent(CartridgeNaming.surfaceCartridgeFileName(surfaceCode: surface)),
            now: a.now())
        report.lines.append("\(result.surfaceId).db rev \(result.publishedRevision) — \(result.mediaFileCount) file(s)")

        let files = try await a.store.mediaFiles().count
        report.lines.append("\(files) media files (\(a.produced.count) selected assets), "
                            + "\(a.produced.reduce(0) { $0 + $1.renditions.count }) generated renditions, "
                            + "\(sessions.count) sessions, \(sets.count) session sets, "
                            + "\(try await a.store.allDirectives().count) directives")
        try await a.finish()
        return report
    }
}
