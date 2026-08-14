// iMessageNotifier.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation

/// Backup notification channel via Messages.app (iMessage).
///
/// Used as a fallback when Telegram is unreachable or in parallel mode.
/// Requires Messages.app to be signed in and Automation TCC permission granted
/// once. All sends go through `/usr/bin/osascript`.
class iMessageNotifier {
    static let shared = iMessageNotifier()

    // MARK: - Availability

    /// True when the recipient is configured. Does NOT guarantee Messages is
    /// logged in / TCC granted — that can only be discovered by sending.
    var isConfigured: Bool {
        recipient != nil && MessagesApp.isInstalled
    }

    var recipient: String? {
        AppSettings.shared.imessageRecipient.nonEmpty
    }

    // MARK: - Sends (non-blocking)

    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        guard let recipient = recipient else {
            NotificationLog.log("iMessage send skipped - no recipient configured")
            return false
        }
        let script = """
        tell application "Messages"
            set targetBuddy to buddy "\(recipient)"
            send "\(scriptSafe(text))" to targetBuddy
        end tell
        """
        return run(script, payload: "text \(text.count) chars")
    }

    @discardableResult
    func sendPhoto(path: String, caption: String) -> Bool {
        guard let recipient = recipient else {
            NotificationLog.log("iMessage photo send skipped - no recipient configured")
            return false
        }
        guard FileManager.default.fileExists(atPath: path) else {
            NotificationLog.log("iMessage photo send skipped - file missing: \(path)")
            return false
        }
        // The caption is sent as a separate text first, then the photo.
        if !caption.isEmpty {
            _ = sendMessage("[MacGuard] \(caption)")
        }
        let script = """
        tell application "Messages"
            set targetBuddy to buddy "\(recipient)"
            send POSIX file "\(path)" to targetBuddy
        end tell
        """
        return run(script, payload: "photo \(path)")
    }

    // MARK: - Private

    private func scriptSafe(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\\", with: "/")
    }

    private func run(_ script: String, payload: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                NotificationLog.log("iMessage sent: \(payload)")
                if !output.isEmpty { NotificationLog.log("iMessage osascript: \(output)") }
                return true
            } else {
                NotificationLog.log("iMessage failed (exit \(process.terminationStatus)): \(output)")
                return false
            }
        } catch {
            NotificationLog.log("iMessage osascript launch error: \(error)")
            return false
        }
    }
}

// MARK: - Messages app presence

enum MessagesApp {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/System/Applications/Messages.app")
    }
}