//
//  VideoARCaptureManager.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation
import ARKit
import AVFoundation
import Combine
import simd

@MainActor
final class VideoARCaptureManager: NSObject, ObservableObject {
    @Published var session = ARSession()
    @Published var isRecording = false
    @Published var captureError: String?
    @Published var latestRecording: VideoARCaptureResult?
    @Published var isSessionRunning = false

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

    override init() {
        super.init()
        session.delegate = self
        imuRecorder.setUpdateInterval(0.01)
    }

    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            captureError = "ARKit world tracking is not supported on this device."
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        if let format = configuration.videoFormat(forFPS: 30) {
            configuration.videoFormat = format
        }
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
}

extension VideoARCaptureManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.latestTransform = frame.camera.transform
            guard self.isRecording else { return }
            self.startVideoWriterIfNeeded(pixelBuffer: frame.capturedImage)
            self.videoRecorder.appendFrame(frame.capturedImage, timestamp: frame.timestamp)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.captureError = error.localizedDescription
        }
    }
}

private extension ARWorldTrackingConfiguration {
    func videoFormat(forFPS fps: Int) -> ARConfiguration.VideoFormat? {
        return type(of: self).supportedVideoFormats.first { format in
            format.framesPerSecond == fps
        }
    }
}
