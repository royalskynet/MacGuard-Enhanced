// CameraCaptureManager.swift
// MacGuard - Anti-Theft Alarm for macOS (Enhanced)
// Created: 2026-08-14

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import AppKit

/// Captures photo evidence on a loop while the alarm is active, saving JPEGs
/// under `captures/` and routing them to the notification channels.
///
/// Degradation ladder (never crashes, always logs):
/// 1. Hardware camera via AVFoundation.
/// 2. If no camera / camera permission denied → fall back to a screen capture.
/// 3. If that also fails → log and skip (alarm flow unaffected).
final class CameraCaptureManager: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = CameraCaptureManager()

    // MARK: - State

    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.macguard.camera", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var timer: Timer?
    private var insideCapture = false
    private var useScreenshotFallback = false

    // MARK: - Loop control

    func startCaptureLoop(interval: Int) {
        stopCaptureLoop()
        let seconds = max(2, interval)
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            self?.capturePhoto()
        }
        capturePhoto()
    }

    func stopCaptureLoop() {
        timer?.invalidate()
        timer = nil
        sessionQueue.async { [weak self] in
            self?.teardownSession()
        }
    }

    /// Take a single photo immediately (used for the pre-alarm snapshot too).
    func capturePhoto() {
        sessionQueue.async { [weak self] in
            self?.runCapture()
        }
    }

    // MARK: - Capture

    private func runCapture() {
        guard !insideCapture else { return }
        insideCapture = true
        defer { insideCapture = false }

        if useScreenshotFallback {
            screenshotCapture()
            return
        }

        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        switch auth {
        case .authorized:
            break
        case .notDetermined:
            SVCapture.request { [weak self] granted in
                guard let self else { return }
                if !granted { self.useScreenshotFallback = true; self.screenshotCapture() }
            }
            return
        default:
            useScreenshotFallback = true
            screenshotCapture()
            return
        }

        ensureSession()
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    private func ensureSession() {
        if session == nil {
            session = buildSession()
        }
        guard let session, !session.isRunning else { return }
        session.startRunning()
    }

    private func buildSession() -> AVCaptureSession? {
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else {
            NotificationLog.log("Camera unavailable - switching to screenshot fallback")
            useScreenshotFallback = true
            return nil
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        self.session = session
        return session
    }

    private func teardownSession() {
        if let session, session.isRunning {
            session.stopRunning()
        }
        self.session = nil
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            NotificationLog.log("Camera capture error: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            NotificationLog.log("Camera capture produced no data")
            return
        }
        saveAndRoute(data)
    }

    // MARK: - Screenshot fallback

    private func screenshotCapture() {
        guard let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            NotificationLog.log("Screenshot fallback failed (screen recording permission?) - skipped")
            return
        }
        guard let data = cgImageAsJPEG(image) else {
            NotificationLog.log("Screenshot fallback - JPEG encoding failed")
            return
        }
        saveAndRoute(data)
    }

    private func cgImageAsJPEG(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    // MARK: - Persistence & routing

    private func saveAndRoute(_ data: Data) {
        let dir = NotifierPaths.capturesDir
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let name = "MacGuard_\(f.string(from: Date()))_evidence.jpg"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            NotificationLog.log("Evidence captured: \(url.path)")
            let caption = "🚨 Evidence captured \(f.string(from: Date()))"
            NotificationRouter.shared.sendPhoto(path: url.path, caption: caption)
        } catch {
            NotificationLog.log("Evidence save failed: \(error)")
        }
    }
}

// MARK: - Video auth request helper

enum SVCapture {
    static func request(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}