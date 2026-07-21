import Foundation
import MarqueeDataKit

// Builds a reference Marquee.db using the SHIPPING Swift migrator, so the
// shared schema repo can be verified against Swift's actual output.
let out = CommandLine.arguments[1]
try? FileManager.default.removeItem(atPath: out)
let store = try MarqueeStore(path: out)
_ = try await store.createProject(cloudUid: "00000000-0000-0000-0000-000000000000",
                                  name: "Reference", now: 0)
print("wrote \(out)")
