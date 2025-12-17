//
//  VideoARCaptureManager.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation
import CoreGraphics
import ARKit
import AVFoundation
import Combine
import simd

struct ARVideoFormatOption: Identifiable, Equatable, Hashable {
    let id = UUID()
    let format: ARConfiguration.VideoFormat
    let resolution: CGSize
    let fps: Int

    var label: String {
        "\(Int(resolution.width))×\(Int(resolution.height)) @ \(fps)fps"
    }

    static func == (lhs: ARVideoFormatOption, rhs: ARVideoFormatOption) -> Bool {
        lhs.resolution == rhs.resolution && lhs.fps == rhs.fps
    }
}

final class VideoARCaptureManager: NSObject, ObservableObject {
    @Published var session = ARSession()
    @Published var isRecording = false
    @Published var captureError: String?
    @Published var latestRecording: VideoARCaptureResult?
    @Published var isSessionRunning = false
    @Published var availableFormats: [ARVideoFormatOption] = []
    @Published var selectedFormat: ARVideoFormatOption?

    private let imuRecorder = IMUStreamRecorder()
    private let videoRecorder = ARVideoRecorder()
    private var pendingIMUSamples: [IMUSample] = []
    private var pendingARSamples: [ARPoseSample] = []
    private var recordingStartDate: Date?
    private var arTimer: DispatchSourceTimer?
    private var latestTransform: simd_float4x4?
    private var videoTempURL: URL?
    private var videoWriterStarted = false
    private let arSamplingQueue = DispatchQueue(label: "VideoAROdometryQueue")
    private let arDelegateQueue = DispatchQueue(label: "VideoARSessionDelegateQueue")

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = arDelegateQueue
        imuRecorder.setUpdateInterval(0.01)
        refreshAvailableFormats()
    }

    func refreshAvailableFormats() {
        guard ARWorldTrackingConfiguration.isSupported else {
            captureError = "ARKit world tracking is not supported on this device."
            availableFormats = []
            return
        }
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats.map { format in
            ARVideoFormatOption(format: format, resolution: format.imageResolution, fps: format.framesPerSecond)
        }
        let sorted = formats.sorted { lhs, rhs in
            if lhs.resolution.width == rhs.resolution.width {
                return lhs.fps > rhs.fps
            }
            return lhs.resolution.width > rhs.resolution.width
        }
        availableFormats = sorted
        if selectedFormat == nil {
            selectedFormat = sorted.first
        }
    }

    func startSession(using formatOption: ARVideoFormatOption? = nil) {
        let option = formatOption ?? selectedFormat ?? availableFormats.first
        guard let chosen = option else {
            captureError = "No AR video formats are available on this device."
            return
        }
        selectedFormat = chosen
        guard let configuration = makeConfiguration(for: chosen) else { return }
        applyFixedExposure()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    func stopSession() {
        session.pause()
        isSessionRunning = false
    }

    func startRecording() {
        guard !isRecording else { return }
        captureError = nil
        pendingIMUSamples = []
        pendingARSamples = []
        recordingStartDate = Date()
        videoTempURL = nil
        videoWriterStarted = false
        isRecording = true

        imuRecorder.start()
        startARSamplingTimer()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        stopARSamplingTimer()
        pendingIMUSamples = imuRecorder.stop()
        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0

        videoRecorder.stopRecording { [weak self] url in
            guard let self else { return }
            guard let videoURL = url else {
                self.captureError = "Failed to finalize video."
                return
            }
            let result = VideoARCaptureResult(
                videoURL: videoURL,
                imuSamples: self.pendingIMUSamples,
                arSamples: self.pendingARSamples,
                duration: duration
            )
            self.latestRecording = result
        }
    }

    private func startARSamplingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: arSamplingQueue)
        timer.schedule(deadline: .now(), repeating: 0.01)
        timer.setEventHandler { [weak self] in
            guard let self, self.isRecording, let transform = self.latestTransform else { return }
            let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let orientation = simd_quatf(transform)
            let sample = ARPoseSample(
                timestamp: Date(),
                positionX: Double(position.x),
                positionY: Double(position.y),
                positionZ: Double(position.z),
                orientationX: Double(orientation.vector.x),
                orientationY: Double(orientation.vector.y),
                orientationZ: Double(orientation.vector.z),
                orientationW: Double(orientation.vector.w)
            )
            DispatchQueue.main.async {
                self.pendingARSamples.append(sample)
            }
        }
        arTimer = timer
        timer.resume()
    }

    private func stopARSamplingTimer() {
        arTimer?.cancel()
        arTimer = nil
    }

    private func applyFixedExposure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        do {
            try device.lockForConfiguration()
            let targetSeconds = 0.01
            let minSeconds = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
            let maxSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
            let clamped = max(minSeconds, min(maxSeconds, targetSeconds))
            let duration = CMTimeMakeWithSeconds(clamped, preferredTimescale: 1_000_000_000)
            device.setExposureModeCustom(duration: duration, iso: device.iso) { _ in }
            device.unlockForConfiguration()
        } catch {
            captureError = "Failed to set exposure: \(error.localizedDescription)"
        }
    }

    private func startVideoWriterIfNeeded(pixelBuffer: CVPixelBuffer) {
        guard !videoWriterStarted else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        do {
            let url = try videoRecorder.startRecording(frameSize: CGSize(width: width, height: height))
            videoTempURL = url
            videoWriterStarted = true
        } catch {
            captureError = "Failed to start video recording: \(error.localizedDescription)"
        }
    }

    func updateResolution(to option: ARVideoFormatOption) {
        guard !isRecording else {
            captureError = "Stop recording to change resolution."
            return
        }
        selectedFormat = option
        guard let configuration = makeConfiguration(for: option) else { return }
        applyFixedExposure()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    private func makeConfiguration(for option: ARVideoFormatOption) -> ARWorldTrackingConfiguration? {
        guard ARWorldTrackingConfiguration.isSupported else {
            captureError = "ARKit world tracking is not supported on this device."
            return nil
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.videoFormat = option.format
        return configuration
    }
}

extension VideoARCaptureManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        autoreleasepool {
            let transform = frame.camera.transform
            let pixelBuffer = frame.capturedImage
            let timestamp = frame.timestamp

            DispatchQueue.main.async { [weak self] in
                self?.latestTransform = transform
            }

            arSamplingQueue.async { [weak self] in
                guard let self, self.isRecording else { return }
                self.startVideoWriterIfNeeded(pixelBuffer: pixelBuffer)
                self.videoRecorder.appendFrame(pixelBuffer, timestamp: timestamp)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.captureError = error.localizedDescription
        }
    }
}
