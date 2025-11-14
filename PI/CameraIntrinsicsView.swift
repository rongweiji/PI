//
//  CameraIntrinsicsView.swift
//  PI
//
//  Created by Rongwei Ji on 11/28/25.
//

import SwiftUI
import AVFoundation
import Combine
import simd

struct CameraIntrinsicsView: View {
    @StateObject private var manager = CameraIntrinsicsManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                previewSection
                calibrationInfoSection
                helperSection
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Camera Intrinsics")
        .onDisappear {
            manager.stopSession()
        }
    }

    private var previewSection: some View {
        Group {
            if let error = manager.cameraError {
                Text(error)
                    .multilineTextAlignment(.center)
                    .frame(height: 260)
                    .padding(.horizontal)
            } else if manager.isAuthorized && manager.isSessionRunning {
                CameraView(session: manager.session)
                    .frame(height: 260)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else if manager.isAuthorized {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Starting camera…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Text("Camera access is required.")
                    .frame(height: 260)
                    .padding(.horizontal)
            }
        }
    }

    private var calibrationInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intrinsic Matrix")
                .font(.headline)

            if let matrix = manager.intrinsicMatrix {
                let rows = manager.matrixRows(matrix)
                ForEach(rows.indices, id: \.self) { index in
                    Text(rows[index])
                        .font(.system(.body, design: .monospaced))
                }

                if let dimensions = manager.referenceDimensions {
                    Text("Frame Dimensions: \(Int(dimensions.width)) × \(Int(dimensions.height)) px")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let timestamp = manager.lastUpdate {
                    Text("Last Updated: \(timestamp.formatted(date: .numeric, time: .standard))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if manager.isSessionRunning {
                Text("Waiting for calibration data from the live camera feed…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start the camera preview to stream and display intrinsic data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var helperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera intrinsics are extracted per-frame using Core Media attachments (kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix). No still capture is required.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }
}

final class CameraIntrinsicsManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var cameraError: String?
    @Published var intrinsicMatrix: simd_float3x3?
    @Published var referenceDimensions: CGSize?
    @Published var lastUpdate: Date?
    @Published var isAuthorized = false
    @Published var isSessionRunning = false

    private let sessionQueue = DispatchQueue(label: "CameraIntrinsicsSessionQueue")
    private let videoOutputQueue = DispatchQueue(label: "CameraIntrinsicsVideoOutputQueue")
    private let videoOutput = AVCaptureVideoDataOutput()

    override init() {
        super.init()
        checkAuthorization()
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
                    } else {
                        self?.cameraError = "Camera permission is required."
                    }
                }
            }
        default:
            isAuthorized = false
            cameraError = "Camera permission is required."
        }
    }

    func setupSession() {
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

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                videoOutput.alwaysDiscardsLateVideoFrames = true

                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
                } else {
                    DispatchQueue.main.async {
                        self.cameraError = "Unable to read video frames on this device."
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

            self.configureIntrinsicDelivery()

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
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

    func matrixRows(_ matrix: simd_float3x3) -> [String] {
        let rows = [
            [matrix.columns.0.x, matrix.columns.1.x, matrix.columns.2.x],
            [matrix.columns.0.y, matrix.columns.1.y, matrix.columns.2.y],
            [matrix.columns.0.z, matrix.columns.1.z, matrix.columns.2.z]
        ]
        return rows.map { row in
            String(format: "[%9.3f %9.3f %9.3f]", row[0], row[1], row[2])
        }
    }

    private func configureIntrinsicDelivery() {
        guard let connection = videoOutput.connection(with: .video),
              connection.isCameraIntrinsicMatrixDeliverySupported else {
            return
        }
        connection.isCameraIntrinsicMatrixDeliveryEnabled = true
    }
}

extension CameraIntrinsicsManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard
            let rawData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) as? Data,
            rawData.count == MemoryLayout<matrix_float3x3>.size
        else {
            return
        }

        let matrix = rawData.withUnsafeBytes { buffer in
            buffer.load(as: matrix_float3x3.self)
        }

        let dimensions: CGSize?
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            dimensions = CGSize(width: width, height: height)
        } else {
            dimensions = nil
        }

        DispatchQueue.main.async {
            self.intrinsicMatrix = matrix
            self.referenceDimensions = dimensions
            self.lastUpdate = Date()
        }
    }
}
