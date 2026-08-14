// WiFiMonitor.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation
import CoreWLAN

/// Notifies the alarm manager when the currently-connected Wi-Fi drops while
/// armed, so an untrusted-network disconnect can act as an extra trigger source.
class WiFiMonitor {
    weak var delegate: WiFiMonitorDelegate?

    private var timer: Timer?
    private var lastSSID: String?

    func startMonitoring() {
        stopMonitoring()
        lastSSID = currentSSID
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        lastSSID = nil
    }

    var isMonitoring: Bool { timer != nil }

    /// Current Wi-Fi SSID, or nil when offline / Wi-Fi off.
    var currentSSID: String? {
        guard let iface = CWWiFiClient.shared().interface() else { return nil }
        return iface.ssid()
    }

    private func check() {
        let ssid = currentSSID
        let hadWiFi = (lastSSID?.isEmpty == false)

        if ssid == nil || ssid?.isEmpty == true {
            // Currently offline. If we had a network before, that's a disconnect.
            if hadWiFi {
                NotificationLog.log("Wi-Fi disconnected (was on '\(lastSSID ?? "?")')")
                delegate?.wifiDisconnected()
            }
            lastSSID = ssid
        } else {
            // Connected (or first sample). Just record and compare next tick.
            if hadWiFi && lastSSID != nil && ssid != lastSSID {
                NotificationLog.log("Wi-Fi changed '\(lastSSID ?? "?")' → '\(ssid!)'")
            }
            lastSSID = ssid
        }
    }
}

protocol WiFiMonitorDelegate: AnyObject {
    func wifiDisconnected()
}