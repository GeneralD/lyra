#!/usr/bin/env swift
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let lyraWindows = windows.filter { ($0["kCGWindowOwnerName"] as? String) == "lyra" }

guard !lyraWindows.isEmpty else {
    print("FAIL: no lyra windows found")
    exit(1)
}

for w in lyraWindows {
    let pid = w["kCGWindowOwnerPID"] as? Int ?? 0
    let bounds = w["kCGWindowBounds"] as? [String: Int] ?? [:]
    let width = bounds["Width"] ?? 0
    let height = bounds["Height"] ?? 0
    let memory = w["kCGWindowMemoryUsage"] as? Int ?? 0
    let onscreen = w["kCGWindowIsOnscreen"] as? Bool ?? false

    guard width > 0, height > 0 else {
        print("FAIL: lyra window has zero size (PID=\(pid))")
        exit(1)
    }

    let minMemory = width * height  // at least 1 byte per pixel as sanity check
    guard memory > minMemory else {
        print("FAIL: lyra window is likely blank (PID=\(pid) \(width)x\(height) memory=\(memory) expected>\(minMemory))")
        exit(1)
    }

    print("OK: lyra overlay active (PID=\(pid) \(width)x\(height) memory=\(memory) onscreen=\(onscreen))")
}
