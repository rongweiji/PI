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
import CoreImage
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

    private let frameWriterQueue = DispatchQueue(label: "VideoARFrameWriterQueue")
    private let arDelegateQueue = DispatchQueue(label: "VideoARSessionDelegateQueue")
    private let ciContext = CIContext()
    private var recordingFolderURL: URL?
    private var framesFolderURL: URL?
    private var timestampsURL: URL?
    private var poseCSVURL: URL?
    private var timestampsHandle: FileHandle?
    private var poseHandle: FileHandle?
    private var frameIndex = 0
    private var firstFrameTimestamp: TimeInterval?
    private var lastFrameTimestamp: TimeInterval?
    private var activeRecordingToken: UUID?

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = arDelegateQueue
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
        if let selected = selectedFormat {
            if !sorted.contains(selected) {
                selectedFormat = preferredDefaultFormat(from: sorted)
            }
        } else {
            selectedFormat = preferredDefaultFormat(from: sorted)
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
        guard activeRecordingToken == nil else {
            captureError = "Please wait for the previous capture to finish saving."
            return
        }
        captureError = nil
        do {
            try prepareRecordingSession()
            activeRecordingToken = UUID()
            isRecording = true
        } catch {
            captureError = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        let token = activeRecordingToken
        frameWriterQueue.async { [weak self] in
            self?.finalizeRecording(expectedToken: token)
        }
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

    private func preferredDefaultFormat(from options: [ARVideoFormatOption]) -> ARVideoFormatOption? {
        let matches = options.filter {
            Int($0.resolution.width) == 640 && Int($0.resolution.height) == 480
        }
        return matches.sorted(by: { $0.fps > $1.fps }).first ?? options.first
    }

    private func prepareRecordingSession() throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("ARFrames-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let framesFolder = tempBase.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: framesFolder, withIntermediateDirectories: true)

        let timestampsFile = tempBase.appendingPathComponent("timestamps.txt")
        let poseFile = tempBase.appendingPathComponent("pose.csv")

        let timestampsHeader = "filename,timestamp\n"
        let poseHeader = "timestamp,posX,posY,posZ,quatX,quatY,quatZ,quatW\n"

        FileManager.default.createFile(atPath: timestampsFile.path, contents: timestampsHeader.data(using: .utf8))
        FileManager.default.createFile(atPath: poseFile.path, contents: poseHeader.data(using: .utf8))

        let timestampsHandle = try FileHandle(forWritingTo: timestampsFile)
        timestampsHandle.seekToEndOfFile()
        let poseHandle = try FileHandle(forWritingTo: poseFile)
        poseHandle.seekToEndOfFile()

        recordingFolderURL = tempBase
        framesFolderURL = framesFolder
        timestampsURL = timestampsFile
        poseCSVURL = poseFile
        self.timestampsHandle = timestampsHandle
        self.poseHandle = poseHandle
        frameIndex = 0
        firstFrameTimestamp = nil
        lastFrameTimestamp = nil
    }

    private func finalizeRecording(expectedToken: UUID?) {
        guard let framesFolderURL, let timestampsURL, let poseCSVURL, let recordingFolderURL else {
            DispatchQueue.main.async { [weak self] in
                self?.captureError = "Recording data was not prepared."
            }
            return
        }
        guard let expectedToken, expectedToken == activeRecordingToken else { return }

        do {
            try timestampsHandle?.close()
            try poseHandle?.close()
            timestampsHandle = nil
            poseHandle = nil

            let zipURL = recordingFolderURL.appendingPathComponent("frames.zip")
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            try ZipWriter.createZip(from: framesFolderURL, to: zipURL)
            try? FileManager.default.removeItem(at: framesFolderURL)

            let duration: TimeInterval
            if let firstFrameTimestamp, let lastFrameTimestamp, lastFrameTimestamp >= firstFrameTimestamp {
                duration = lastFrameTimestamp - firstFrameTimestamp
            } else {
                duration = 0
            }

            let result = VideoARCaptureResult(
                framesZipURL: zipURL,
                timestampsURL: timestampsURL,
                poseCSVURL: poseCSVURL,
                duration: duration,
                frameCount: frameIndex
            )

            DispatchQueue.main.async { [weak self] in
                self?.latestRecording = result
            }
            activeRecordingToken = nil
        } catch {
            activeRecordingToken = nil
            DispatchQueue.main.async { [weak self] in
                self?.captureError = "Failed to finalize frames: \(error.localizedDescription)"
            }
        }
    }

    private func makeJPEGData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:])
    }

    private func writeFrameData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    private func appendTimestampLine(filename: String, timestamp: TimeInterval) {
        guard let handle = timestampsHandle else { return }
        let line = "\(filename),\(String(format: "%.9f", timestamp))\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func appendPoseLine(timestamp: TimeInterval, transform: simd_float4x4) {
        guard let handle = poseHandle else { return }
        let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let orientation = simd_quatf(transform)
        let line = [
            String(format: "%.9f", timestamp),
            String(format: "%.6f", position.x),
            String(format: "%.6f", position.y),
            String(format: "%.6f", position.z),
            String(format: "%.6f", orientation.vector.x),
            String(format: "%.6f", orientation.vector.y),
            String(format: "%.6f", orientation.vector.z),
            String(format: "%.6f", orientation.vector.w)
        ].joined(separator: ",") + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }
}

extension VideoARCaptureManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording, let token = activeRecordingToken, let framesFolderURL = framesFolderURL else { return }
        let transform = frame.camera.transform
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp

        guard let jpegData = makeJPEGData(from: pixelBuffer) else {
            DispatchQueue.main.async { [weak self] in
                self?.captureError = "Failed to encode JPEG frame."
            }
            return
        }

        frameWriterQueue.async { [weak self] in
            guard let self, token == self.activeRecordingToken else { return }
            autoreleasepool {
                self.frameIndex += 1
                let filename = String(format: "%07d.jpg", self.frameIndex)
                let frameURL = framesFolderURL.appendingPathComponent(filename)

                do {
                    try self.writeFrameData(jpegData, to: frameURL)
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.captureError = "Failed to write frame: \(error.localizedDescription)"
                    }
                    return
                }

                if self.firstFrameTimestamp == nil {
                    self.firstFrameTimestamp = timestamp
                }
                self.lastFrameTimestamp = timestamp
                self.appendTimestampLine(filename: filename, timestamp: timestamp)
                self.appendPoseLine(timestamp: timestamp, transform: transform)
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.captureError = error.localizedDescription
        }
    }
}

private enum ZipWriter {
    static func createZip(from folderURL: URL, to zipURL: URL) throws {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .nameKey]
        let fileURLs = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Array(resourceKeys), options: [.skipsHiddenFiles])
        let sortedFiles = fileURLs.filter { url in
            (try? url.resourceValues(forKeys: resourceKeys).isRegularFile) ?? false
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        fileManager.createFile(atPath: zipURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: zipURL)
        defer { try? handle.close() }

        var centralDirectory = Data()
        var localHeaderOffset: UInt32 = 0

        for fileURL in sortedFiles {
            let filename = fileURL.lastPathComponent
            guard let filenameData = filename.data(using: .utf8) else { continue }
            let fileData = try Data(contentsOf: fileURL)
            let crc = CRC32.checksum(fileData)
            let size = UInt32(fileData.count)

            var localHeader = Data()
            localHeader.appendUInt32(0x04034b50)
            localHeader.appendUInt16(20)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(size)
            localHeader.appendUInt32(size)
            localHeader.appendUInt16(UInt16(filenameData.count))
            localHeader.appendUInt16(0)

            handle.write(localHeader)
            handle.write(filenameData)
            handle.write(fileData)

            var centralHeader = Data()
            centralHeader.appendUInt32(0x02014b50)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(20)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(crc)
            centralHeader.appendUInt32(size)
            centralHeader.appendUInt32(size)
            centralHeader.appendUInt16(UInt16(filenameData.count))
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt16(0)
            centralHeader.appendUInt32(0)
            centralHeader.appendUInt32(localHeaderOffset)

            centralDirectory.append(centralHeader)
            centralDirectory.append(filenameData)

            localHeaderOffset += UInt32(localHeader.count) + UInt32(filenameData.count) + size
        }

        let centralDirectoryOffset = localHeaderOffset
        handle.write(centralDirectory)

        var endRecord = Data()
        endRecord.appendUInt32(0x06054b50)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(0)
        endRecord.appendUInt16(UInt16(sortedFiles.count))
        endRecord.appendUInt16(UInt16(sortedFiles.count))
        endRecord.appendUInt32(UInt32(centralDirectory.count))
        endRecord.appendUInt32(centralDirectoryOffset)
        endRecord.appendUInt16(0)

        handle.write(endRecord)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index in
            var crc = UInt32(index)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = 0xEDB88320 ^ (crc >> 1)
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
