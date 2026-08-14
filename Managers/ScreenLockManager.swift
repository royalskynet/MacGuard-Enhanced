// ScreenLockManager.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation
import CoreGraphics
import IOKit

/// Locks the macOS login session and detects whether the screen is locked.
///
/// Lock uses the system `CGSession -suspend` binary, which suspends the current
/// login session (same effect as selecting "Lock Screen" in the menu bar).
class ScreenLockManager {
    static let shared = ScreenLockManager()

    /// Suspends (locks) the current GUI login session.
    @discardableResult
    func lockScreen() -> Bool {
        let path = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        guard FileManager.default.fileExists(atPath: path) else {
            NotificationLog.log("Lock screen skipped - CGSession binary not found")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-suspend"]
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            NotificationLog.log("Screen lock request: \(ok ? "ok" : "exit \(process.terminationStatus)")")
            return ok
        } catch {
            NotificationLog.log("Screen lock launch error: \(error)")
            return false
        }
    }

    /// True when the current GUI session is screen-locked.
    var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [CFString: Any] else {
            return false
        }
        return (session["CGSSessionScreenIsLocked" as CFString] as? Bool) ?? false
    }
}