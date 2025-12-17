//
//  VideoOnlyCaptureManager.swift
//  PI
//
//  Created by Rongwei Ji on 12/16/25.
//

import Foundation
import AVFoundation
import Combine
import UIKit

enum VideoOnlyResolution: String, CaseIterable, Identifiable {
    case r1920x1440
    case r640x480

    var id: String { rawValue }

    var label: String {
        switch self {
        case .r1920x1440: return "1920×1440"
        case .r640x480: return "640×480"
        }
    }

    var dimensions: CMVideoDimensions {
        switch self {
        case .r1920x1440: return CMVideoDimensions(width: 1920, height: 1440)
        case .r640x480: return CMVideoDimensions(width: 640, height: 480)
        }
    }
}

final class VideoOnlyCaptureManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var cameraError: String?
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var captureError: String?
    @Published var latestRecording: (url: URL, duration: TimeInterval)?
    @Published var selectedResolution: VideoOnlyResolution = .r1920x1440

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "VideoOnlySessionQueue")
    private var recordingStartDate: Date?
    private var activeCameraDevice: AVCaptureDevice?

    override init() {
        super.init()
        configureOrientationMonitoring()
        checkAuthorization()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async {
                self.cameraError = nil
                self.isSessionRunning = false
            }

            session.beginConfiguration()

            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    DispatchQueue.main.async {
                        self.cameraError = "Camera is not available on this device."
                    }
                    session.commitConfiguration()
                    return
                }

                let input = try AVCaptureDeviceInput(device: device)
                self.activeCameraDevice = device

                if session.canAddInput(input) {
                    session.addInput(input)
                } else {
                    DispatchQueue.main.async {
                        self.cameraError = "Unable to add camera input."
                    }
                }

                if session.canAddOutput(movieOutput) {
                    session.addOutput(movieOutput)
                    movieOutput.movieFragmentInterval = .invalid
                } else {
                    DispatchQueue.main.async {
                        self.cameraError = "Unable to record videos on this device."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.cameraError = "Failed to configure the camera: \(error.localizedDescription)"
                }
            }

            self.applyResolution(self.selectedResolution)

            session.commitConfiguration()

            if !session.isRunning {
                session.startRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func updateResolution(to resolution: VideoOnlyResolution) {
        guard !isRecording else {
            captureError = "Stop recording to change resolution."
            return
        }
        selectedResolution = resolution
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            self.applyResolution(resolution)
            session.commitConfiguration()
        }
    }

    func startRecording() {
        guard isSessionRunning, !isRecording else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")

            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }

            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            self.recordingStartDate = Date()

            DispatchQueue.main.async {
                self.isRecording = true
                self.captureError = nil
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    func stopSession() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
                DispatchQueue.main.async {
                    self?.isSessionRunning = false
                }
            }
        }
    }

    private func applyResolution(_ resolution: VideoOnlyResolution) {
        guard let device = activeCameraDevice else { return }
        let target = resolution.dimensions

        guard let format = device.formats.first(where: { format in
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let supports30 = format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= 30 && range.maxFrameRate >= 30
            }
            return dims.width == target.width && dims.height == target.height && supports30
        }) else {
            DispatchQueue.main.async {
                self.captureError = "Resolution \(resolution.label) @30fps not supported on this device."
            }
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.captureError = "Failed to set resolution: \(error.localizedDescription)"
            }
        }
    }

    private func configureOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConnectionOrientation()
        }
    }

    private func updateConnectionOrientation() {
        let orientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) ?? .portrait
        if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }
}

extension VideoOnlyCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartDate = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }

        if let error {
            DispatchQueue.main.async {
                self.captureError = "Recording failed: \(error.localizedDescription)"
            }
            return
        }

        DispatchQueue.main.async {
            self.latestRecording = (url: outputFileURL, duration: duration)
        }
    }
}
