//
//  CameraView.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import AVFoundation
import Combine
import Foundation

final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        guard let connection = previewLayer.connection else { return }

        if #unavailable(iOS 17.0), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

struct CameraCapture {
    let data: Data
    let metadata: Data?
    let previewImage: UIImage?
}

struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var capturedImage: UIImage?
    @Published var capturedPhotoData: Data?
    @Published var capturedPhotoMetadata: Data?
    @Published var latestCapture: CameraCapture?
    @Published var captureError: String?
    @Published var isAuthorized = false
    @Published var cameraError: String?
    @Published var isSessionRunning = false
    @Published var isCapturingPhoto = false

    private var photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "CameraSessionQueue")

    override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async {
                self.cameraError = nil
                self.isSessionRunning = false
            }

            session.beginConfiguration()
            session.sessionPreset = .photo

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

                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                } else {
                    DispatchQueue.main.async {
                        self.cameraError = "Unable to capture photos on this device."
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

    func capturePhoto() {
        guard isSessionRunning else {
            captureError = "Camera is still starting. Please try again."
            return
        }

        capturedPhotoData = nil
        capturedPhotoMetadata = nil
        capturedImage = nil
        latestCapture = nil
        captureError = nil
        isCapturingPhoto = true

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func stopSession() {
        if session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.stopRunning()
                DispatchQueue.main.async { [weak self] in
                    self?.isSessionRunning = false
                }
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.captureError = error.localizedDescription
                self.isCapturingPhoto = false
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), !data.isEmpty else {
            DispatchQueue.main.async {
                self.captureError = "Camera returned empty data."
                self.isCapturingPhoto = false
            }
            return
        }

        DispatchQueue.main.async {
            let metadataData = try? PropertyListSerialization.data(
                fromPropertyList: photo.metadata as NSDictionary,
                format: .binary,
                options: 0
            )
            let image = UIImage(data: data)

            self.capturedPhotoData = data
            self.capturedPhotoMetadata = metadataData
            self.capturedImage = image
            self.latestCapture = CameraCapture(data: data, metadata: metadataData, previewImage: image)
            self.captureError = nil
            self.isCapturingPhoto = false
        }
    }
}
