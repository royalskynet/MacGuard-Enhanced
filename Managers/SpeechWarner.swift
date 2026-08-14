// SpeechWarner.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14
//
// The red-flash / pulsing countdown overlay lives in CountdownOverlayView
// (pre-existing). This class adds the SPOKEN warning layer on top of it.

import Foundation
import AppKit

/// Speaks an audible warning out loud during the triggered countdown so the
/// intruder (and bystanders) are unmistakably notified the Mac is protected.
///
/// Speaking runs in the background and never blocks the alarm state machine.
class SpeechWarner {
    static let shared = SpeechWarner()

    private let synthesizer = NSSpeechSynthesizer()
    private var timer: Timer?

    /// Begin the warning loop. Speaks an initial alert, then repeats a warning
    /// every few seconds until `stop()` is called.
    /// - Parameter countdown: configured countdown duration (0 = immediate).
    func start(countdown: Int) {
        stop()
        synthesizer.rate = 175

        if countdown > 0 {
            speak("Warning. Unauthorized access detected. The alarm will sound in \(countdown) seconds.")
        } else {
            speak("Warning. Unauthorized access detected. Alarm active.")
        }

        // Repeating warning cadence while the countdown runs.
        timer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            self?.speak("This Mac is protected by MacGuard. Move away.")
        }
    }

    /// Silently confirm the alarm is now active (called on `.alarming`).
    func announceActive() {
        synthesizer.stopSpeaking()
        speak("ALARM ACTIVE. This Mac is reported as stolen.")
    }

    /// Stop speaking and cancel the loop.
    func stop() {
        timer?.invalidate()
        timer = nil
        synthesizer.stopSpeaking()
    }

    private func speak(_ text: String) {
        guard !synthesizer.isSpeaking else { return }
        synthesizer.startSpeaking(text)
    }
}