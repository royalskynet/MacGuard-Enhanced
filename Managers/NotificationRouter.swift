// NotificationRouter.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation

/// Unified notification faucet. Routes alarm events and captured photos to
/// Telegram (primary) and optionally iMessage (backup) according to the
/// configured `imessageMode`.
class NotificationRouter {
    static let shared = NotificationRouter()

    private let telegram = TelegramNotifier.shared
    private let imessage = iMessageNotifier.shared

    private init() {
        // Wire the Telegram queue's exhaustion hook back to the backup channel.
        telegram.fallbackHandler = { [weak self] item in
            guard let self else { return }
            guard self.mode == .fallback else { return }
            self.sendToBackup(item)
        }
    }

    /// Current backup routing mode.
    private var mode: iMessageMode {
        AppSettings.shared.imessageMode
    }

    // MARK: - Public API

    /// Route an alarm lifecycle event to the configured channels.
    func notify(_ event: NotificationEvent) {
        let text = event.title + "\n" + event.message + "\n" + timestampString()
        telegram.sendMessage(text)

        if mode == .parallel, imessage.isConfigured {
            imessage.sendMessage("[MacGuard] " + event.title + "\n" + event.message)
        } else if mode == .off || mode == .fallback {
            // Telegram-only now; fallback mode escalates only after retries exhaust.
        }
    }

    /// Route a captured photo (with caption) to the configured channels.
    func sendPhoto(path: String, caption: String) {
        telegram.sendPhoto(path: path, caption: caption)

        if mode == .parallel, imessage.isConfigured {
            imessage.sendPhoto(path: path, caption: caption)
        }
    }

    /// Test buttons used from Settings.
    func testTelegram(completion: @escaping (String, [String: Any]?) -> Void) {
        telegram.testDelivery(completion: completion)
    }

    @discardableResult
    func testiMessage() -> Bool {
        imessage.sendMessage("MacGuard test message \(Int(Date().timeIntervalSince1970))")
    }

    // MARK: - Backup escalation

    private func sendToBackup(_ item: PendingNotification) {
        guard imessage.isConfigured else {
            NotificationLog.log("Fallback: iMessage not configured, skipping backup")
            return
        }
        switch item.type {
        case .photo:
            if let path = item.photoPath {
                imessage.sendPhoto(path: path, caption: item.text)
            }
        case .text:
            imessage.sendMessage("[MacGuard] " + item.text)
        }
    }

    private func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}