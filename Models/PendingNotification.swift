// PendingNotification.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation

/// Notification delivery channel
enum NotificationChannel: String, Codable {
    case telegram
    case imessage
}

/// Notification payload type
enum NotificationPayloadType: String, Codable {
    case text
    case photo
}

/// A single pending notification persisted as one JSON file on disk.
/// Used by the offline-safe retry queue so alarm events survive network loss.
struct PendingNotification: Codable, Identifiable {
    let id: UUID
    var type: NotificationPayloadType
    /// For `.text`: the message body. For `.photo`: the caption.
    var text: String
    /// Absolute path to the photo file for `.photo` payloads.
    var photoPath: String?
    var timestamp: Date
    var retryCount: Int
    var channel: NotificationChannel

    init(
        id: UUID = UUID(),
        type: NotificationPayloadType,
        text: String,
        photoPath: String? = nil,
        timestamp: Date = Date(),
        retryCount: Int = 0,
        channel: NotificationChannel
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.photoPath = photoPath
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.channel = channel
    }
}

// MARK: - Shared storage paths

/// Central path helpers for the enhanced modules.
enum NotifierPaths {
    /// ~/Library/Application Support/MacGuard/
    static var baseDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacGuard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ~/Library/Application Support/MacGuard/queue/
    static var queueDir: URL {
        let dir = baseDir.appendingPathComponent("queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ~/Library/Application Support/MacGuard/captures/
    static var capturesDir: URL {
        let dir = baseDir.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Notification event

/// High-level alarm lifecycle events routed to notification channels.
enum NotificationEvent {
    case armed
    case trigger
    case alarming
    case disarmed

    var title: String {
        switch self {
        case .armed: return "🛡 MacGuard - ARMED"
        case .trigger: return "⚠️ MacGuard - INTRUSION DETECTED"
        case .alarming: return "🚨 MacGuard - ALARM ACTIVE"
        case .disarmed: return "✅ MacGuard - Disarmed"
        }
    }

    var message: String {
        switch self {
        case .armed: return "Anti-theft mode is now active."
        case .trigger: return "Unauthorized access detected on your Mac. Photo evidence is being captured."
        case .alarming: return "ALARM ACTIVE. This Mac is reported as stolen. Authorities / owner notified."
        case .disarmed: return "Alarm disarmed successfully."
        }
    }
}

// MARK: - String convenience

extension String {
    /// `nil` when the string is empty or whitespace-only.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}