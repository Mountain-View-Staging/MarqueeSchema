//
//  Shows.swift — the shows, as an author would build them in Studio.
//
//  RIG26  the workhorse: seven venue days in America/New_York, three surface configs, each
//         with ONE playlist schedule, which a device plays with the files of the orientation
//         it renders (plan D-r2-30) — PORT1 (the Rotation, one location, a portrait sign: a
//         portrait device fetches only its lane's files), TAKE1 (~1,000 directives:
//         standing, takeover and OFF across the days, two locations) and DEMO1 (a
//         DemoStation: the Rotation, whose picture-in-picture is the same rotation in the
//         other orientation's files; a still and a video background, a transparent and an
//         opaque overlay) — over items with portrait-only, landscape-only, both-slot and
//         square files, a session board with a video backing, a project default backing and
//         wallpapers in both slots. Its structure follows the dev show the harnesses used to
//         read (days, directive cadence), with generated content only.
//
//  EDIT26 the editor sample: the 12-entry "TEST — Editor parity" playlist, row for row,
//         trim for trim, flag for flag, with its three directives on the fourth row (entry
//         id 5) on 2026-10-06 in America/Chicago, over freshly generated test patterns.
//

import Foundation
import MarqueeDataKit

struct ShowReport {
    let code: String
    var lines: [String] = []
}

// MARK: - RIG26

enum Rig26 {
    static let code = "RIG26"
    static let zoneName = "America/New_York"
    static let zone = TimeZone(identifier: zoneName)!
    static let days = ["2026-08-27", "2026-08-28", "2026-08-29", "2026-08-30",
                       "2026-08-31", "2026-09-01", "2026-09-02"]
    /// Authoring starts a week before Day 1; everything is published the day before it.
    static let authoringStart = Venue.utc("2026-08-20T12:00:00Z")
    static let publishAt = Venue.utc("2026-08-26T12:00:00Z")

    static func build(into showsDir: URL) async throws -> ShowReport {
        let a = try await Author.create(in: showsDir, code: code, name: "Test rig",
                                        cloudUid: "00000000-0000-4000-8000-000000000126",
                                        timezone: zoneName, start: authoringStart)
        var report = ShowReport(code: code)
        let dayRows = try await a.setDays(days, zone: zone)
        let day1 = dayRows[0].startTime
        func at(_ dayIndex: Int, _ hour: Int, _ minute: Int = 0) -> Int64 {
            Venue.instant(days[dayIndex], hour: hour, minute: minute, zone: zone)
        }
        func tag(_ n: Int) -> String { "\(code) · file \(String(format: "%02d", n))" }

        // ── Stills ───────────────────────────────────────────────────────────
        let full: [Author.StillRendition] = [.optimized, .web]
        let alphaSet: [Author.StillRendition] = [.optimized, .skipWeb("already web-ready (PNG with alpha)")]
        let barsL = try await a.still(StillSpec(file: "rig-bars-landscape.png", width: 1920, height: 1080, style: .bars,
                                                title: "BARS", subtitle: "LANDSCAPE · 1920 × 1080 · PNG", tag: tag(1)),
                                      as: .png, renditions: full)
        let barsP = try await a.still(StillSpec(file: "rig-bars-portrait.png", width: 1080, height: 1920, style: .bars,
                                                title: "BARS", subtitle: "PORTRAIT · 1080 × 1920 · PNG", tag: tag(2)),
                                      as: .png, renditions: full)
        let square = try await a.still(StillSpec(file: "rig-square.png", width: 1080, height: 1080, style: .card(hue: 0.58),
                                                 title: "SQUARE", subtitle: "1080 × 1080 · both slots · holds 5 s", tag: tag(3)),
                                       as: .png, renditions: full)
        let cardL = try await a.still(StillSpec(file: "rig-card-landscape.jpg", width: 1920, height: 1080, style: .card(hue: 0.08),
                                                title: "CARD", subtitle: "LANDSCAPE · 1920 × 1080 · JPEG", tag: tag(4)),
                                      as: .jpeg, renditions: full)
        let cardP = try await a.still(StillSpec(file: "rig-card-portrait.jpg", width: 1080, height: 1920, style: .card(hue: 0.08),
                                                title: "CARD", subtitle: "PORTRAIT · 1080 × 1920 · JPEG", tag: tag(5)),
                                      as: .jpeg, renditions: full)
        let photoL = try await a.still(StillSpec(file: "rig-photo-landscape.heic", width: 3840, height: 2160, style: .photo(hue: 0.62),
                                                 title: "PHOTO 4K", subtitle: "LANDSCAPE · 3840 × 2160 · HEIC", tag: tag(6)),
                                       as: .heic, quality: 0.75, renditions: full)
        let photoP = try await a.still(StillSpec(file: "rig-photo-portrait.heic", width: 2160, height: 3840, style: .photo(hue: 0.62),
                                                 title: "PHOTO 4K", subtitle: "PORTRAIT · 2160 × 3840 · HEIC", tag: tag(7)),
                                       as: .heic, quality: 0.75, renditions: full)
        let portraitOnly = try await a.still(StillSpec(file: "rig-portrait-only.png", width: 1080, height: 1920, style: .card(hue: 0.33),
                                                       title: "PORTRAIT ONLY", subtitle: "no landscape file · 1080 × 1920 · PNG", tag: tag(8)),
                                             as: .png, renditions: full)
        let landscapeOnly = try await a.still(StillSpec(file: "rig-landscape-only.jpg", width: 1920, height: 1080, style: .card(hue: 0.9),
                                                        title: "LANDSCAPE ONLY", subtitle: "no portrait file · 1920 × 1080 · JPEG", tag: tag(9)),
                                              as: .jpeg, renditions: full)
        let webp = try await a.still(StillSpec(file: "rig-webp-landscape.webp", width: 1920, height: 1080, style: .card(hue: 0.47),
                                               title: "WEBP", subtitle: "LANDSCAPE · 1920 × 1080 · WebP original", tag: tag(10)),
                                     as: .webp, quality: 0.8,
                                     renditions: [.optimized, .skipWeb("already web-ready (WebP)")])
        let oversize = try await a.still(StillSpec(file: "rig-oversize.png", width: 5000, height: 2813, style: .bars,
                                                   title: "OVERSIZE", subtitle: "5000 × 2813 · over the 3840 px ceiling · PNG", tag: tag(11)),
                                         as: .png, renditions: full)
        let lowerThird = try await a.still(StillSpec(file: "rig-lower-third.png", width: 1920, height: 1080, style: .lowerThird,
                                                     title: "LOWER THIRD", subtitle: "transparent PNG · plays over the backing", tag: tag(12)),
                                           as: .png, renditions: alphaSet)
        let demoBgL = try await a.still(StillSpec(file: "rig-demo-background-landscape.png", width: 1920, height: 1080, style: .card(hue: 0.72),
                                                  title: "DEMO BACKGROUND", subtitle: "still · LANDSCAPE", tag: tag(13)),
                                        as: .png, renditions: full)
        let demoBgP = try await a.still(StillSpec(file: "rig-demo-background-portrait.png", width: 1080, height: 1920, style: .card(hue: 0.72),
                                                  title: "DEMO BACKGROUND", subtitle: "still · PORTRAIT", tag: tag(14)),
                                        as: .png, renditions: full)
        let overlayL = try await a.still(StillSpec(file: "rig-overlay-landscape.png", width: 1920, height: 1080, style: .frameOverlay(hue: 0.72),
                                                   title: "DEMO OVERLAY", subtitle: "transparent · LANDSCAPE", tag: tag(15)),
                                         as: .png, renditions: alphaSet)
        let overlayP = try await a.still(StillSpec(file: "rig-overlay-portrait.png", width: 1080, height: 1920, style: .frameOverlay(hue: 0.72),
                                                   title: "DEMO OVERLAY", subtitle: "transparent · PORTRAIT", tag: tag(16)),
                                         as: .png, renditions: alphaSet)
        let overlayOpaque = try await a.still(StillSpec(file: "rig-overlay-opaque.jpg", width: 1920, height: 1080, style: .card(hue: 0.0),
                                                        title: "OPAQUE OVERLAY", subtitle: "JPEG · no transparency · covers the picture-in-picture", tag: tag(17)),
                                              as: .jpeg, renditions: full)
        let showWallL = try await a.still(StillSpec(file: "rig-wallpaper-show-landscape.png", width: 1920, height: 1080, style: .bands(hue: 0.55),
                                                    title: "SHOW WALLPAPER", subtitle: "LANDSCAPE", tag: tag(18)),
                                          as: .png, renditions: full)
        let showWallP = try await a.still(StillSpec(file: "rig-wallpaper-show-portrait.png", width: 1080, height: 1920, style: .bands(hue: 0.55),
                                                    title: "SHOW WALLPAPER", subtitle: "PORTRAIT", tag: tag(19)),
                                          as: .png, renditions: full)
        let deskWallL = try await a.still(StillSpec(file: "rig-wallpaper-desktop-landscape.png", width: 1920, height: 1080, style: .bands(hue: 0.15),
                                                    title: "DESKTOP WALLPAPER", subtitle: "LANDSCAPE", tag: tag(20)),
                                          as: .png, renditions: full)
        let deskWallP = try await a.still(StillSpec(file: "rig-wallpaper-desktop-portrait.png", width: 1080, height: 1920, style: .bands(hue: 0.15),
                                                    title: "DESKTOP WALLPAPER", subtitle: "PORTRAIT", tag: tag(21)),
                                          as: .png, renditions: full)
        let backingL = try await a.still(StillSpec(file: "rig-backing-landscape.png", width: 1920, height: 1080, style: .bands(hue: 0.66),
                                                   title: "DEFAULT BACKING", subtitle: "LANDSCAPE · behind transparent content", tag: tag(22)),
                                         as: .png, renditions: full)
        let backingP = try await a.still(StillSpec(file: "rig-backing-portrait.png", width: 1080, height: 1920, style: .bands(hue: 0.66),
                                                   title: "DEFAULT BACKING", subtitle: "PORTRAIT · behind transparent content", tag: tag(23)),
                                         as: .png, renditions: full)
        let logo = try await a.still(StillSpec(file: "rig-logo.png", width: 800, height: 240, style: .logo,
                                               title: "LOGO", subtitle: "board logo · transparent", tag: tag(24)),
                                     as: .png, renditions: alphaSet)
        let miniA = try await a.still(StillSpec(file: "rig-mini-a.png", width: 1080, height: 1920, style: .card(hue: 0.12),
                                                title: "MINI A", subtitle: "mini player · PORTRAIT · PNG", tag: tag(25)),
                                      as: .png, renditions: full)
        let miniB = try await a.still(StillSpec(file: "rig-mini-b.jpg", width: 1080, height: 1920, style: .card(hue: 0.52),
                                                title: "MINI B", subtitle: "mini player · PORTRAIT · JPEG", tag: tag(26)),
                                      as: .jpeg, renditions: full)

        // ── Clips ────────────────────────────────────────────────────────────
        let wifiSet: [Author.ClipRendition] = [.optimized(bitRate: 1_200_000), .web(bitRate: 1_000_000), .wifi(bitRate: 500_000)]
        let twoSet: [Author.ClipRendition] = [.optimized(bitRate: 1_000_000), .web(bitRate: 900_000)]
        let countdownL = try await a.clip(ClipSpec(file: "rig-countdown-landscape-h264.mp4", width: 1920, height: 1080, seconds: 10,
                                                   style: .countdown, hue: 0.6, title: "TEST COUNTDOWN · H.264 · LANDSCAPE", tag: tag(27)),
                                          codec: .h264, bitRate: 2_500_000, renditions: wifiSet)
        let countdownP = try await a.clip(ClipSpec(file: "rig-countdown-portrait-h264.mp4", width: 1080, height: 1920, seconds: 10,
                                                   style: .countdown, hue: 0.6, title: "TEST COUNTDOWN · H.264 · PORTRAIT", tag: tag(28)),
                                          codec: .h264, bitRate: 2_500_000, renditions: wifiSet)
        let countdownHEVC = try await a.clip(ClipSpec(file: "rig-countdown-landscape-hevc.mp4", width: 1920, height: 1080, seconds: 10,
                                                      style: .countdown, hue: 0.95, title: "TEST COUNTDOWN · HEVC · LANDSCAPE", tag: tag(29)),
                                             codec: .hevc, bitRate: 1_500_000,
                                             renditions: [.optimized(bitRate: 1_000_000), .web(bitRate: 1_000_000), .wifi(bitRate: 450_000)])
        let loopL = try await a.clip(ClipSpec(file: "rig-loop-landscape.mp4", width: 1920, height: 1080, seconds: 20,
                                              style: .loop, hue: 0.3, title: "LOOP 20 s · LANDSCAPE", tag: tag(30)),
                                     codec: .h264, bitRate: 2_000_000, renditions: twoSet)
        let loopP = try await a.clip(ClipSpec(file: "rig-loop-portrait.mp4", width: 1080, height: 1920, seconds: 20,
                                              style: .loop, hue: 0.3, title: "LOOP 20 s · PORTRAIT", tag: tag(31)),
                                     codec: .h264, bitRate: 2_000_000, renditions: twoSet)
        let boardBgL = try await a.clip(ClipSpec(file: "rig-board-backing-landscape.mp4", width: 1920, height: 1080, seconds: 12,
                                                 style: .backing, hue: 0.62, title: "BOARD BACKING · video · LANDSCAPE", tag: tag(32)),
                                        codec: .h264, bitRate: 1_500_000, renditions: twoSet)
        let boardBgP = try await a.clip(ClipSpec(file: "rig-board-backing-portrait.mp4", width: 1080, height: 1920, seconds: 12,
                                                 style: .backing, hue: 0.62, title: "BOARD BACKING · video · PORTRAIT", tag: tag(33)),
                                        codec: .h264, bitRate: 1_500_000, renditions: twoSet)
        let demoVidL = try await a.clip(ClipSpec(file: "rig-demo-background-landscape.mp4", width: 1920, height: 1080, seconds: 15,
                                                 style: .backing, hue: 0.78, title: "DEMO BACKGROUND · video · LANDSCAPE", tag: tag(34)),
                                        codec: .h264, bitRate: 1_500_000, renditions: twoSet)
        let demoVidP = try await a.clip(ClipSpec(file: "rig-demo-background-portrait.mp4", width: 1080, height: 1920, seconds: 15,
                                                 style: .backing, hue: 0.78, title: "DEMO BACKGROUND · video · PORTRAIT", tag: tag(35)),
                                        codec: .h264, bitRate: 1_500_000, renditions: twoSet)
        let miniLoop = try await a.clip(ClipSpec(file: "rig-mini-loop-portrait.mp4", width: 1080, height: 1920, seconds: 8,
                                                 style: .loop, hue: 0.05, title: "MINI LOOP · PORTRAIT", tag: tag(36)),
                                        codec: .h264, bitRate: 1_500_000,
                                        renditions: [.optimized(bitRate: 900_000), .web(bitRate: 800_000), .wifi(bitRate: 400_000)])

        // ── Items ────────────────────────────────────────────────────────────
        let bars = try await a.item("Bars", portrait: barsP, landscape: barsL)
        let squareItem = try await a.item("Square (holds 5 s)", portrait: square, landscape: square, displayDuration: 5)
        let card = try await a.item("Card", portrait: cardP, landscape: cardL)
        let photo = try await a.item("Photo 4K (HEIC)", portrait: photoP, landscape: photoL)
        let portraitOnlyItem = try await a.item("Portrait only", portrait: portraitOnly)
        let landscapeOnlyItem = try await a.item("Landscape only", landscape: landscapeOnly)
        let webpItem = try await a.item("WebP still", landscape: webp)
        let oversizeItem = try await a.item("Oversize still (5000 px)", landscape: oversize)
        let lowerThirdItem = try await a.item("Lower third (alpha)", landscape: lowerThird)
        let countdown = try await a.item("Countdown 10 s", portrait: countdownP, landscape: countdownL)
        let countdownHEVCItem = try await a.item("Countdown HEVC", landscape: countdownHEVC)
        let loop = try await a.item("Loop 20 s", portrait: loopP, landscape: loopL)
        let boardBacking = try await a.item("Board backing (video)", portrait: boardBgP, landscape: boardBgL)
        let demoStill = try await a.item("Demo background (still)", portrait: demoBgP, landscape: demoBgL)
        let demoVideo = try await a.item("Demo background (video)", portrait: demoVidP, landscape: demoVidL)
        let overlayClear = try await a.item("Demo overlay (transparent)", portrait: overlayP, landscape: overlayL)
        let overlaySolid = try await a.item("Demo overlay (opaque)", landscape: overlayOpaque)
        let showWallpaper = try await a.item("Show wallpaper", portrait: showWallP, landscape: showWallL)
        let desktopWallpaper = try await a.item("Desktop wallpaper", portrait: deskWallP, landscape: deskWallL)
        let defaultBacking = try await a.item("Default backing", portrait: backingP, landscape: backingL)
        let logoItem = try await a.item("Board logo", portrait: logo, landscape: logo)
        let miniAItem = try await a.item("Mini player A", portrait: miniA)
        let miniBItem = try await a.item("Mini player B", portrait: miniB)
        let miniLoopItem = try await a.item("Mini player loop", portrait: miniLoop)

        // ── The session board: one room, four sessions a day for seven days ──
        // Shaped like an imported room: the schedule layout, presenters with an employer
        // (`companyName`), attributes indexed by id and by name, a Role repeated, and no
        // Featuring attribute — the conventions the board readers are pinned to.
        let stamp = a.now()
        let set = try await a.store.insertSessionSet(SessionSet(
            name: "Main room", duration: 8,
            backingItemId: boardBacking.id, logoItemId: logoItem.id, created: stamp, updated: stamp))
        let slots: [(Int, Int, Int, Int, String, String)] = [
            (9, 0, 9, 45, "Opening remarks", "Keynote"), (10, 30, 11, 15, "Panel discussion", "Breakout"),
            (13, 0, 13, 45, "Hands-on workshop", "Workshop"), (15, 30, 16, 15, "Closing notes", "Breakout"),
        ]
        var sessionCount = 0
        for (d, day) in days.enumerated() {
            for (n, slot) in slots.enumerated() {
                sessionCount += 1
                let label = "D\(d + 1)-\(n + 1)"
                let companies = [["Example Company A", "Example Company E"], ["Example Company B", "Example Company F"],
                                 ["Example Company C", "Example Company G"], ["Example Company D", "Example Company H"]][n]
                let presenters = """
                [{"firstName":"Presenter","lastName":"\(label)A","fullName":"Presenter \(label)A","jobTitle":"Speaker","companyName":"\(companies[0])"},\
                {"firstName":"Presenter","lastName":"\(label)B","fullName":"Presenter \(label)B","jobTitle":"Speaker","companyName":"\(companies[1])"}]
                """
                let track = d % 2 == 0 ? "Track A" : "Track B"
                let attributes = """
                [{"attributeId":"SessionType","attribute":"Session Type","value":"\(slot.5)"},\
                {"attributeId":"Role","attribute":"Role","value":"Role one"},\
                {"attributeId":"Role","attribute":"Role","value":"Role two"},\
                {"attributeId":"Track","attribute":"Track","value":"\(track)"}]
                """
                let t = a.now()
                let session = try await a.store.insertSession(Session(
                    name: "\(slot.4) (\(label))",
                    abstract: "Placeholder abstract for a generated test session, day \(d + 1) slot \(n + 1).",
                    presenters: presenters, attributes: attributes, created: t, updated: t))
                _ = try await a.store.insertSessionSetEntry(SessionSetEntry(
                    sessionSetId: set.id!, sessionId: session.id!,
                    startTime: Venue.instant(day, hour: slot.0, minute: slot.1, zone: zone),
                    endTime: Venue.instant(day, hour: slot.2, minute: slot.3, zone: zone),
                    roomName: "Main room", created: t, updated: t))
            }
        }

        // ── Playlists ────────────────────────────────────────────────────────
        let daily: [(DirectiveType, Int64, Bool)] = (0..<days.count).map { (.standard, at($0, 0), true) }

        // The rotation: fifteen entries on a standing daily ON, three with no directive
        // at all (they never play), one of the fifteen disabled (a Studio Player flag a
        // Surface never sees), a trimmed clip, a board, and every media shape.
        let rotation = try await a.playlist("Rotation")
        var rotationEntries: [PlaylistEntry] = []
        for item in [bars, card, photo, countdown, portraitOnlyItem, landscapeOnlyItem, squareItem, webpItem,
                     loop, oversizeItem, lowerThirdItem, countdownHEVCItem] {
            rotationEntries.append(try await a.append(item, to: rotation))
        }
        rotationEntries.append(try await a.store.appendSessionSet(playlistId: rotation.id!, sessionSetId: set.id!, now: a.now()))
        let trimmed = try await a.append(countdown, to: rotation)
        for side in [SurfaceOrientation.portrait, .landscape] {
            try await a.store.setEntryWindow(side, startTime: 2.0, endTime: 6.5, forEntry: trimmed.id!, now: a.now())
        }
        rotationEntries.append(trimmed)
        let disabled = try await a.append(card, to: rotation)
        try await a.store.setEntryPlaybackState(.disabled, true, forEntry: disabled.id!, now: a.now())
        rotationEntries.append(disabled)
        // The loop plays 2 → 12 s in landscape only: a per-orientation window.
        try await a.store.setEntryWindow(.landscape, startTime: 2.0, endTime: 12.0,
                                         forEntry: rotationEntries[8].id!, now: a.now())
        for entry in rotationEntries { try await a.direct(entry, daily, zone: zoneName) }
        for item in [bars, loop, photo] { _ = try await a.append(item, to: rotation) }   // no directive

        // The takeovers: two standing entries, one standard on the hour, two takeovers
        // at :10 and :30, each armed OFF at authoring time — 1,025 directives.
        let takeovers = try await a.playlist("Takeovers")
        let standing1 = try await a.append(bars, to: takeovers)
        let standing2 = try await a.append(card, to: takeovers)
        let hourly = try await a.append(loop, to: takeovers)
        let takeoverA = try await a.append(countdown, to: takeovers)
        let takeoverB = try await a.append(photo, to: takeovers)
        try await a.direct(standing1, daily, zone: zoneName)
        try await a.direct(standing2, daily, zone: zoneName)
        func cadence(_ type: DirectiveType, on: Int, off: Int) -> [(DirectiveType, Int64, Bool)] {
            var rules: [(DirectiveType, Int64, Bool)] = [(type, a.clock, false)]
            for d in 0..<days.count {
                for h in 0..<24 {
                    rules.append((type, at(d, h, on), true))
                    rules.append((type, at(d, h, off), false))
                }
            }
            return rules
        }
        try await a.direct(hourly, cadence(.standard, on: 0, off: 50), zone: zoneName)
        try await a.direct(takeoverA, cadence(.takeover, on: 10, off: 20), zone: zoneName)
        try await a.direct(takeoverB, cadence(.takeover, on: 30, off: 40), zone: zoneName)

        // The mini player: before one schedule (D-r2-30) the portrait lane a landscape
        // DemoStation showed in its PIP. The PIP is now the Rotation, moved, so this playlist
        // is scheduled nowhere: an unscheduled playlist no cartridge carries.
        let mini = try await a.playlist("Mini player")
        for item in [miniAItem, miniBItem, miniLoopItem] {
            try await a.direct(try await a.append(item, to: mini), daily, zone: zoneName)
        }

        // ── Project: the default backing and the two wallpapers ─────────────
        try await a.store.setProjectBacking(itemId: defaultBacking.id, now: a.now())
        try await a.store.setShowWallpaper(itemId: showWallpaper.id, now: a.now())
        try await a.store.setDesktopWallpaper(itemId: desktopWallpaper.id, now: a.now())

        // ── Surfaces ─────────────────────────────────────────────────────────
        func config(_ surfaceId: String, _ name: String, locations: [(String, String)]) async throws -> SurfaceConfig {
            let t = a.now()
            let row = try await a.store.insertSurfaceConfig(SurfaceConfig(surfaceId: surfaceId, name: name, created: t, updated: t))
            for (locationId, label) in locations {
                let lt = a.now()
                _ = try await a.store.insertSurfaceLocation(SurfaceLocation(
                    configId: row.id!, locationId: locationId, label: label, created: lt, updated: lt))
            }
            return row
        }
        let authored = a.clock
        let port1 = try await config("PORT1", "Portrait rotation", locations: [("PORT1-A", "Portrait sign")])
        try await a.store.schedulePlaylist(configId: port1.id!, playlistId: rotation.id!, timestamp: authored, now: a.now())
        try await a.store.schedulePlaylist(configId: port1.id!, playlistId: rotation.id!, timestamp: day1, now: a.now())

        let take1 = try await config("TAKE1", "Takeovers",
                                     locations: [("TAKE1-A", "Takeover sign — hall"), ("TAKE1-B", "Takeover sign — lobby")])
        try await a.store.schedulePlaylist(configId: take1.id!, playlistId: takeovers.id!, timestamp: authored, now: a.now())

        let demo1 = try await config("DEMO1", "Demo station", locations: [("DEMO1-A", "Demo station")])
        try await a.store.schedulePlaylist(configId: demo1.id!, playlistId: rotation.id!, timestamp: authored, now: a.now())
        try await a.store.scheduleDemo(configId: demo1.id!, backgroundItemId: demoStill.id!, overlayItemId: overlayClear.id!,
                                       timestamp: authored + 1000, now: a.now())
        try await a.store.scheduleDemo(configId: demo1.id!, backgroundItemId: demoVideo.id!, overlayItemId: overlaySolid.id!,
                                       timestamp: dayRows[1].startTime, now: a.now())
        try await a.store.scheduleDemoOff(configId: demo1.id!, timestamp: at(2, 18), now: a.now())
        try await a.store.scheduleDemo(configId: demo1.id!, backgroundItemId: demoStill.id!,
                                       timestamp: dayRows[3].startTime, now: a.now())

        // ── Publish: project.db, then every surface ─────────────────────────
        a.advance(to: publishAt)
        let root = a.project.root
        let projectResult = try await a.store.publishProjectCartridge(
            to: root.appendingPathComponent(CartridgeNaming.projectCartridgeFileName), now: a.now())
        report.lines.append("project.db rev \(projectResult.publishedRevision) — \(projectResult.mediaFileCount) file(s)")
        for surface in [port1, take1, demo1] {
            let result = try await a.store.publishCartridge(
                configId: surface.id!,
                to: root.appendingPathComponent(CartridgeNaming.surfaceCartridgeFileName(surfaceCode: surface.surfaceId!)),
                now: a.now())
            report.lines.append("\(result.surfaceId).db rev \(result.publishedRevision) — \(result.mediaFileCount) file(s)")
        }

        let directiveCount = try await a.store.allDirectives().count
        report.lines.append("\(a.produced.count) media files, \(a.produced.reduce(0) { $0 + $1.renditions.count }) generated renditions, "
                            + "\(try await a.service.listItems().count) items, \(sessionCount) sessions, \(directiveCount) directives")
        try await a.finish()
        return report
    }
}

// MARK: - EDIT26

enum Edit26 {
    static let code = "EDIT26"
    static let zoneName = "America/Chicago"
    static let zone = TimeZone(identifier: zoneName)!
    static let day = "2026-10-06"
    static let authoringStart = Venue.utc("2026-09-25T12:00:00Z")
    static let publishAt = Venue.utc("2026-09-26T12:00:00Z")

    static func build(into showsDir: URL) async throws -> ShowReport {
        let a = try await Author.create(in: showsDir, code: code, name: "Editor sample",
                                        cloudUid: "00000000-0000-4000-8000-000000000226",
                                        timezone: zoneName, start: authoringStart)
        var report = ShowReport(code: code)
        let days = try await a.setDays([day], zone: zone)
        guard days[0].startTime == 1_791_262_800_000, days[0].endTime == 1_791_349_199_999 else {
            throw GenError.check("EDIT26's day is not the pinned 2026-10-06 in Chicago: \(days[0])")
        }
        func tag(_ n: Int) -> String { "\(code) · file \(String(format: "%02d", n))" }

        // The media of the web Studio's editor fixture, generated fresh: stills whose web
        // rendition the optimizer skips (a PNG is already web-ready), H.264 countdowns with
        // no venue master but a web and a wifi rung, an HEVC countdown with all three.
        let pngOnly: [Author.StillRendition] = [.optimized, .skipWeb("already web-ready (PNG)")]
        let barsL = try await a.still(StillSpec(file: "test-bars-landscape.png", width: 1920, height: 1080, style: .bars,
                                                title: "TEST", subtitle: "LANDSCAPE · 1920 × 1080", tag: tag(1)),
                                      as: .png, renditions: pngOnly)
        let barsP = try await a.still(StillSpec(file: "test-bars-portrait.png", width: 1080, height: 1920, style: .bars,
                                                title: "TEST", subtitle: "PORTRAIT · 1080 × 1920", tag: tag(2)),
                                      as: .png, renditions: pngOnly)
        let square = try await a.still(StillSpec(file: "test-bars-square.png", width: 1080, height: 1080, style: .bars,
                                                 title: "TEST", subtitle: "SQUARE · 1080 × 1080 · fits both slots", tag: tag(3)),
                                       as: .png, renditions: pngOnly)
        let lower = try await a.still(StillSpec(file: "test-lower-third-alpha.png", width: 1920, height: 1080, style: .lowerThird,
                                                title: "TEST lower third", subtitle: "transparent PNG", tag: tag(4)),
                                      as: .png, renditions: pngOnly)
        let noMaster: Author.ClipRendition = .skipOptimized("no venue master for this clip (generated fixture)")
        let cdL = try await a.clip(ClipSpec(file: "test-countdown-landscape-h264.mp4", width: 1920, height: 1080, seconds: 10,
                                            style: .countdown, hue: 0.6, title: "TEST COUNTDOWN · H.264 · LANDSCAPE", tag: tag(5)),
                                   codec: .h264, bitRate: 2_500_000,
                                   renditions: [noMaster, .web(bitRate: 900_000), .wifi(bitRate: 500_000)])
        let cdP = try await a.clip(ClipSpec(file: "test-countdown-portrait-h264.mp4", width: 1080, height: 1920, seconds: 10,
                                            style: .countdown, hue: 0.6, title: "TEST COUNTDOWN · H.264 · PORTRAIT", tag: tag(6)),
                                   codec: .h264, bitRate: 2_500_000,
                                   renditions: [noMaster, .web(bitRate: 900_000), .wifi(bitRate: 500_000)])
        let cdHEVC = try await a.clip(ClipSpec(file: "test-countdown-landscape-hevc.mp4", width: 1920, height: 1080, seconds: 10,
                                               style: .countdown, hue: 0.95, title: "TEST COUNTDOWN · HEVC · LANDSCAPE", tag: tag(7)),
                                      codec: .hevc, bitRate: 1_500_000,
                                      renditions: [.optimized(bitRate: 1_000_000), .web(bitRate: 900_000), .wifi(bitRate: 450_000)])

        let bars = try await a.item("TEST — Bars", portrait: barsP, landscape: barsL)
        let barsPortraitOnly = try await a.item("TEST — Bars (portrait only)", portrait: barsP)
        let squareItem = try await a.item("TEST — Square (holds 5 s)", portrait: square, landscape: square, displayDuration: 5)
        let lowerThird = try await a.item("TEST — Lower third (alpha)", landscape: lower)
        let countdown = try await a.item("TEST — Countdown 10 s", portrait: cdP, landscape: cdL)
        _ = try await a.item("TEST — Countdown (portrait only)", portrait: cdP)
        let countdownHEVC = try await a.item("TEST — Countdown HEVC", landscape: cdHEVC)

        // The sample's ids: playlist 1 is an empty "Untitled Playlist" whose one entry was
        // added and removed, so the parity playlist is id 2 and its entries are ids 2 – 13 —
        // the fourth row is entry id 5, the id the tests and the PRD name.
        let untitled = try await a.playlist("Untitled Playlist")
        let scratch = try await a.append(bars, to: untitled)
        try await a.store.deleteEntry(id: scratch.id!, now: a.now())

        let parity = try await a.playlist("TEST — Editor parity")
        let e1 = try await a.append(bars, to: parity)                  // an untrimmed still (8 s)
        let e2 = try await a.append(squareItem, to: parity)            // a still holding 5 s
        let e3 = try await a.append(bars, to: parity)                  // a still with a 3 s window
        let e4 = try await a.append(countdown, to: parity)             // the untrimmed countdown — the directives
        let e5 = try await a.append(countdown, to: parity)             // trimmed 2.0 → 6.5
        let e6 = try await a.append(countdown, to: parity)             // from 4 s to the end
        let e7 = try await a.append(countdown, to: parity)             // looping
        let e8 = try await a.append(bars, to: parity)                  // pause-in
        let e9 = try await a.append(squareItem, to: parity)            // pause-out
        let e10 = try await a.append(lowerThird, to: parity)           // disabled, landscape only
        let e11 = try await a.append(barsPortraitOnly, to: parity)     // portrait only
        let e12 = try await a.append(countdownHEVC, to: parity)        // HEVC, landscape only
        for side in [SurfaceOrientation.portrait, .landscape] {
            try await a.store.setEntryWindow(side, startTime: 0.0, endTime: 3.0, forEntry: e3.id!, now: a.now())
        }
        for side in [SurfaceOrientation.portrait, .landscape] {
            try await a.store.setEntryWindow(side, startTime: 2.0, endTime: 6.5, forEntry: e5.id!, now: a.now())
        }
        for side in [SurfaceOrientation.portrait, .landscape] {
            try await a.store.setEntryWindow(side, startTime: 4.0, endTime: nil, forEntry: e6.id!, now: a.now())
        }
        try await a.store.setEntryPlaybackState(.loopClip, true, forEntry: e7.id!, now: a.now())
        try await a.store.setEntryPlaybackState(.pauseOnEntry, true, forEntry: e8.id!, now: a.now())
        try await a.store.setEntryPlaybackState(.pauseOnCompletion, true, forEntry: e9.id!, now: a.now())
        try await a.store.setEntryPlaybackState(.disabled, true, forEntry: e10.id!, now: a.now())
        _ = (e1, e2, e11, e12)

        guard e4.id == 5 else { throw GenError.check("the fourth row is entry id \(e4.id ?? -1), not 5") }
        let dayStart = days[0].startTime
        try await a.direct(e4, [
            (.standard, dayStart + 8 * 3_600_000, true),      // 8:00 AM
            (.takeover, dayStart + 12 * 3_600_000, true),     // 12:00 PM
            (.takeover, dayStart + 12 * 3_600_000 + 30 * 60_000, false),  // 12:30 PM
        ], zone: zoneName)

        // One surface scheduling the parity playlist, so a device of either orientation can
        // play the sample and the Loader has a surface cartridge to read. It adds nothing the
        // playlist's rows, trims, flags or directives say.
        let t = a.now()
        let edit1 = try await a.store.insertSurfaceConfig(SurfaceConfig(surfaceId: "EDIT1", name: "Editor sample",
                                                                        created: t, updated: t))
        let lt = a.now()
        _ = try await a.store.insertSurfaceLocation(SurfaceLocation(configId: edit1.id!, locationId: "EDIT1-A",
                                                                    label: "Editor sample sign", created: lt, updated: lt))
        let authored = a.clock
        try await a.store.schedulePlaylist(configId: edit1.id!, playlistId: parity.id!, timestamp: authored, now: a.now())

        a.advance(to: publishAt)
        let root = a.project.root
        let projectResult = try await a.store.publishProjectCartridge(
            to: root.appendingPathComponent(CartridgeNaming.projectCartridgeFileName), now: a.now())
        report.lines.append("project.db rev \(projectResult.publishedRevision) — \(projectResult.mediaFileCount) file(s)")
        let result = try await a.store.publishCartridge(
            configId: edit1.id!, to: root.appendingPathComponent(CartridgeNaming.surfaceCartridgeFileName(surfaceCode: "EDIT1")),
            now: a.now())
        report.lines.append("\(result.surfaceId).db rev \(result.publishedRevision) — \(result.mediaFileCount) file(s)")

        // The rail's running starts (the kit's PlaybackWindow), per orientation.
        let entries = try await a.store.entries(inPlaylist: parity.id!)
        for side in [SurfaceOrientation.portrait, .landscape] {
            var rows: [(counts: Bool, time: Double?)] = []
            for entry in entries {
                let item = try await a.store.mediaItem(id: entry.mediaItemId!)!
                let fileId = side == .portrait ? item.portraitFileId : item.landscapeFileId
                guard let fileId, let file = try await a.store.mediaFile(id: fileId) else {
                    rows.append((false, nil)); continue
                }
                let window = entry.playbackWindow(item: item, file: file, orientation: side)
                rows.append((!entry.disabled, window.runningTime(clipLength: file.intrinsicDuration)))
            }
            let starts = PlaybackWindow.runningStarts(rows).map { $0.map { String(format: "%g", $0) } ?? "—" }
            report.lines.append("running starts, \(side.rawValue): " + starts.joined(separator: ", "))
        }
        report.lines.append("\(a.produced.count) media files, \(a.produced.reduce(0) { $0 + $1.renditions.count }) generated renditions, "
                            + "\(try await a.service.listItems().count) items, \(entries.count) parity entries, "
                            + "\(try await a.store.allDirectives().count) directives")
        try await a.finish()
        return report
    }
}
