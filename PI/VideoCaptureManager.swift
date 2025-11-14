//
//  VideoCaptureManager.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation
import AVFoundation
import UIKit
import Combine

struct VideoCaptureResult {
    let videoURL: URL
    let imuSamples: [IMUSample]
    let duration: TimeInterval
    let previewImage: UIImage?
}

final class VideoCaptureManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var cameraError: String?
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var captureError: String?
    @Published var latestRecording: VideoCaptureResult?

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "VideoCaptureSessionQueue")
    private let imuRecorder = IMUStreamRecorder()
    private var pendingSamples: [IMUSample] = []
    private var recordingStartDate: Date?
    private var currentVideoOrientation: AVCaptureVideoOrientation = .portrait
    private var currentIMUInterval: TimeInterval = 1.0 / 30.0

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
            session.sessionPreset = .high

            do {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    DispatchQueue.main.async {
                        self.cameraError = "Camera is not available on this device."
                    }
                    session.commitConfiguration()
                    return
                }

                let input = try AVCaptureDeviceInput(device: device)

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
                    setVideoOrientation(currentVideoOrientation)
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

            session.commitConfiguration()

            if !session.isRunning {
                session.startRunning()
            }

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
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

            self.setVideoOrientation(self.currentVideoOrientation)
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)

            recordingStartDate = Date()
            imuRecorder.start()

            DispatchQueue.main.async {
                self.isRecording = true
                self.captureError = nil
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            pendingSamples = imuRecorder.stop()
            movieOutput.stopRecording()
        }
    }

    func stopSession() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }

    func updateIMUSamplingInterval(_ interval: TimeInterval) {
        guard !isRecording, interval != currentIMUInterval else { return }
        currentIMUInterval = interval
        imuRecorder.setUpdateInterval(interval)
    }

}

extension VideoCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {}

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let samples = pendingSamples
        pendingSamples = []
        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartDate = nil

        DispatchQueue.main.async {
            self.isRecording = false
        }

        if let error {
            DispatchQueue.main.async {
                self.captureError = error.localizedDescription
            }
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        let previewImage = generatePreview(for: outputFileURL)
        DispatchQueue.main.async {
            self.latestRecording = VideoCaptureResult(
                videoURL: outputFileURL,
                imuSamples: samples,
                duration: duration,
                previewImage: previewImage
            )
        }
    }

    private func generatePreview(for url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

// MARK: - Orientation Handling

private extension VideoCaptureManager {
    func configureOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        if let initialOrientation = AVCaptureVideoOrientation(deviceOrientation: UIDevice.current.orientation) {
            sessionQueue.async { [weak self] in
                self?.setVideoOrientation(initialOrientation)
            }
        }
    }

    @objc func deviceOrientationDidChange() {
        let deviceOrientation = UIDevice.current.orientation
        guard let orientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) else { return }
        sessionQueue.async { [weak self] in
            self?.setVideoOrientation(orientation)
        }
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        currentVideoOrientation = orientation
        if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }
    }
}
