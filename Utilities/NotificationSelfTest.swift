// NotificationSelfTest.swift
// MacGuard (Enhanced) - DEBUG-only self-test
// Invoked via: .build/debug/MacGuard --self-notify
// Exercises the real TelegramNotifier + queue path with a live token + chat id
// already provisioned in Keychain / UserDefaults.

#if DEBUG
import Foundation

enum NotificationSelfTest {
    /// Minimal valid 1×1 transparent PNG (base64) for the photo upload test.
    private static let onePxPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    static func run() {
        print("=== NotificationSelfTest START ===")
        let tg = TelegramNotifier.shared
        print("token present: \(tg.token() != nil)")
        print("chatID: \(AppSettings.shared.telegramChatID.nonEmpty ?? "(none)")")
        print("queue before: \(tg.queueCount())")

        // 1) text message
        tg.sendMessage("MacGuard mini self-test TEXT \(Int(Date().timeIntervalSince1970))")

        // 2) photo message (exercises multipart upload path)
        if let sample = writeSamplePhoto() {
            tg.sendPhoto(path: sample, caption: "MacGuard mini self-test PHOTO \(Int(Date().timeIntervalSince1970))")
        } else {
            print("sample photo write failed - skipping photo send")
        }

        print("queue after enqueue: \(tg.queueCount())")
        print("--- waiting 12s for async drain ---")
        RunLoop.main.run(until: Date().addingTimeInterval(12))
        print("queue after drain wait: \(tg.queueCount())")
        print("=== NotificationSelfTest END ===")
        exit(0)
    }

    private static func writeSamplePhoto() -> String? {
        guard let data = Data(base64Encoded: onePxPNG) else { return nil }
        let url = NotifierPaths.capturesDir.appendingPathComponent("self_test_photo.png")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            print("sample photo write error: \(error)")
            return nil
        }
    }
}
#endif