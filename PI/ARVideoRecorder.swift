//
//  ARVideoRecorder.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import AVFoundation
import CoreVideo

final class ARVideoRecorder {
    private let queue = DispatchQueue(label: "ARVideoRecorderQueue")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private var lastFrameTime: CMTime?
    private let targetFrameDuration = CMTime(value: 1, timescale: 30)
    private var outputURL: URL?

    func startRecording(frameSize: CGSize) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(frameSize.width),
            AVVideoHeightKey: Int(frameSize.height)
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ])

        guard writer.canAdd(input) else {
            throw NSError(domain: "ARVideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add writer input"])
        }
        writer.add(input)

        assetWriter = writer
        videoInput = input
        self.adaptor = adaptor
        startTime = nil
        lastFrameTime = nil
        outputURL = tempURL
        return tempURL
    }

    func appendFrame(_ pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) {
        queue.async { [weak self] in
            guard
                let self,
                let writer = self.assetWriter,
                let input = self.videoInput,
                let adaptor = self.adaptor
            else { return }

            let time = CMTime(seconds: timestamp, preferredTimescale: 600)

            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: time)
                self.startTime = time
                self.lastFrameTime = time
            }

            guard writer.status == .writing else { return }

            if let lastTime = self.lastFrameTime, time - lastTime < self.targetFrameDuration {
                return
            }

            if input.isReadyForMoreMediaData {
                adaptor.append(pixelBuffer, withPresentationTime: time)
                self.lastFrameTime = time
            }
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        queue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let writer = assetWriter, let input = videoInput else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            input.markAsFinished()
            writer.finishWriting {
                DispatchQueue.main.async {
                    completion(self.outputURL)
                }
            }

            self.assetWriter = nil
            self.videoInput = nil
            self.adaptor = nil
            self.startTime = nil
            self.lastFrameTime = nil
        }
    }
}
