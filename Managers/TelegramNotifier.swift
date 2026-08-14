// TelegramNotifier.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation
import Network
import Security

/// Direct Telegram Bot API delivery with an offline-safe on-disk retry queue.
///
/// Design invariants:
/// - The bot token lives in the Keychain (never hard-coded / never in the repo).
/// - chat_id comes from `AppSettings.telegramChatID` (UserDefaults).
/// - Every send is persisted as one `.json` file in the queue dir; failures are
///   retried with exponential backoff (5 → 10 → 30 → 60 s capped) and flushed
///   on network recovery. Queue is capped at 100 items.
/// - Sending never blocks the alarm main flow (all work off the main actor
///   on a serial background queue).
class TelegramNotifier {
    static let shared = TelegramNotifier()

    // MARK: - Keychain

    private let keychainService = "com.shenglong.macguard"
    private let tokenAccount = "telegramBotToken"

    // MARK: - Queue

    private let queueDir: URL
    private let maxQueue = 100
    private let backoffDelays: [TimeInterval] = [5, 10, 30, 60]

    private let session: URLSession
    private let workQueue = DispatchQueue(label: "com.macguard.telegram.work")
    private var isProcessing = false
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.macguard.telegram.nw")

    /// Called by the tail of the drain loop when a Telegram item has exhausted
    /// its retry budget, so the router can escalate to iMessage in fallback mode.
    var fallbackHandler: ((PendingNotification) -> Void)?
    /// Number of failed attempts before triggering the backup channel.
    let fallbackAfterRetries = 5

    // MARK: - Init

    private init() {
        queueDir = NotifierPaths.queueDir
        session = URLSession(configuration: .ephemeral)

        // Flush the queue as soon as the network becomes reachable.
        pathMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                self?.flush()
            }
        }
        pathMonitor?.start(queue: monitorQueue)
    }

    // MARK: - Token storage

    func setToken(_ token: String) {
        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        NotificationLog.log("Telegram token saved (\(status == errSecSuccess ? "ok" : "failed: \(status)"))")
    }

    func token() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token.isEmpty ? nil : token
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public send API (non-blocking)

    @discardableResult
    func sendMessage(_ text: String) -> Bool {
        let item = PendingNotification(type: .text, text: text, channel: .telegram)
        return enqueue(item)
    }

    @discardableResult
    func sendPhoto(path: String, caption: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else {
            NotificationLog.log("Send photo skipped - file missing: \(path)")
            return false
        }
        let item = PendingNotification(type: .photo, text: caption, photoPath: path, channel: .telegram)
        return enqueue(item)
    }

    /// If no token is configured, attempt one synchronous delivery so the UI
    /// test button can show the raw API response.
    func testDelivery(completion: @escaping (String, [String: Any]?) -> Void) {
        guard let token = token(), !token.isEmpty else {
            completion("no_token_saved", nil)
            return
        }
        guard let chatID = AppSettings.shared.telegramChatID.nonEmpty else {
            completion("no_chat_id", nil)
            return
        }
        let text = "MacGuard test message \(Int(Date().timeIntervalSince1970))"
        guard let url = telegramURL(token: token, method: "sendMessage").url else {
            completion("error", ["error": "invalid url"])
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "chat_id=\(chatID)&text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)"
        request.httpBody = body.data(using: .utf8)

        session.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion("error", ["error": error?.localizedDescription ?? "unknown"])
                return
            }
            completion((json["ok"] as? Bool) == true ? "ok" : "error", json)
        }.resume()
    }

    // MARK: - Queueing

    private func enqueue(_ item: PendingNotification) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(item)
            try data.write(to: queueDir.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)

            // Cap queue size (drop oldest)
            pruneQueue()
            flush()
            return true
        } catch {
            NotificationLog.log("Enqueue failed: \(error)")
            return false
        }
    }

    private func pruneQueue() {
        var files = pendingFiles()
        while files.count > maxQueue {
            if let oldest = files.min(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try? FileManager.default.removeItem(at: oldest)
                files = pendingFiles()
            }
        }
    }

    /// Number of queued-but-undelivered notifications on disk.
    func queueCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(at: queueDir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    /// Kick the drain loop if not already running.
    func flush() {
        workQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isProcessing else { return }
            self.isProcessing = true
            self.drainNext()
        }
    }

    /// Recursively drains the queue, one item at a time, applying per-item backoff.
    private func drainNext() {
        guard let item = self.nextPending() else {
            self.isProcessing = false
            return
        }

        attempt(item) { [weak self] success in
            guard let self else { return }
            if success {
                self.remove(item)
                self.workQueue.async { self.drainNext() }
            } else {
                // Keep the item, schedule a retry with exponential backoff.
                self.bumpRetry(item)
                let retries = self.retryCount(item)
                if retries >= self.fallbackAfterRetries {
                    self.fallbackHandler?(item)
                }
                let delay = self.backoffDelays[min(retries - 1, self.backoffDelays.count - 1)]
                self.workQueue.asyncAfter(deadline: .now() + delay) {
                    self.drainNext()
                }
            }
        }
    }

    private func nextPending() -> PendingNotification? {
        for file in pendingFiles() {
            if let item = decode(file) { return item }
        }
        return nil
    }

    private func pendingFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: queueDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private func decode(_ url: URL) -> PendingNotification? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingNotification.self, from: data)
    }

    private func remove(_ item: PendingNotification) {
        try? FileManager.default.removeItem(at: queueDir.appendingPathComponent("\(item.id.uuidString).json"))
    }

    private func bumpRetry(_ item: PendingNotification) {
        guard let data = try? Data(contentsOf: queueDir.appendingPathComponent("\(item.id.uuidString).json")),
              var saved = try? JSONDecoder().decode(PendingNotification.self, from: data) else { return }
        saved.retryCount += 1
        saved.timestamp = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(saved).write(to: queueDir.appendingPathComponent("\(item.id.uuidString).json"), options: .atomic)
    }

    private func retryCount(_ item: PendingNotification) -> Int {
        guard let data = try? Data(contentsOf: queueDir.appendingPathComponent("\(item.id.uuidString).json")),
              let saved = try? JSONDecoder().decode(PendingNotification.self, from: data) else { return item.retryCount }
        return saved.retryCount
    }

    // MARK: - Delivery

    private func attempt(_ item: PendingNotification, completion: @escaping (Bool) -> Void) {
        guard let token = token(), !token.isEmpty else {
            completion(false)
            return
        }
        guard let chatID = AppSettings.shared.telegramChatID.nonEmpty else {
            completion(false)
            return
        }

        let method = item.type == .photo ? "sendPhoto" : "sendMessage"

        guard let url = telegramURL(token: token, method: method).url else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let body: Data
        let contentType: String

        if item.type == .photo, let photoPath = item.photoPath {
            let boundary = "Boundary-\(UUID().uuidString)"
            contentType = "multipart/form-data; boundary=\(boundary)"
            body = multipartBody(boundary: boundary, chatID: chatID, caption: item.text, photoPath: photoPath)
            let size = (try? FileManager.default.attributesOfItem(atPath: photoPath)[.size] as? Int) ?? 0
            NotificationLog.log("Sending photo \(photoPath) (\(size) B)")
        } else {
            contentType = "application/x-www-form-urlencoded"
            let text = (item.text + "\n[\(timestampString(item.timestamp))]")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            body = "chat_id=\(chatID)&text=\(text)".data(using: .utf8) ?? Data()
        }

        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let task = session.dataTask(with: request) { [weak self] data, _, error in
            NotificationLog.log("Telegram \(method): \(error == nil ? "sent" : "error \(error!.localizedDescription)")")
            var ok = error == nil
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                ok = (json["ok"] as? Bool) ?? false
                let desc = (json["description"] as? String) ?? ""
                NotificationLog.log("Telegram API: ok=\(ok)" + (desc.isEmpty ? "" : " desc=\(desc)"))
            }
            self?.handleResult(success: ok)
            completion(ok)
        }
        task.resume()
    }

    private func handleResult(success: Bool) {
        // Hook reserved for future metrics / fallback routing decisions.
    }

    // MARK: - URL helpers

    private func telegramURL(token: String, method: String) -> (url: URL?, string: String) {
        let s = "https://api.telegram.org/bot\(token)/\(method)"
        return (URL(string: s), s)
    }

    /// Build a multipart/form-data body for sendPhoto.
    private func multipartBody(boundary: String, chatID: String, caption: String, photoPath: String) -> Data {
        var body = Data()
        let filename = URL(fileURLWithPath: photoPath).lastPathComponent

        func append(_ string: String) {
            body.append(string.data(using: .utf8) ?? Data())
        }
        func appendData(_ data: Data) {
            body.append(data)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
        append("\(chatID)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
        append("\(caption)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        if let fileData = try? Data(contentsOf: URL(fileURLWithPath: photoPath)) {
            appendData(fileData)
        }
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }

    private func timestampString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Small logging helper

/// Minimal logging used by notification modules (avoids coupling to UI).
enum NotificationLog {
    static func log(_ message: String) {
        print("[MacGuard:Notify] \(message)")
        Task { @MainActor in
            ActivityLogManager.shared.log(.system, message)
        }
    }
}