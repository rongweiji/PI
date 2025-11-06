//
//  PhotoCaptureView.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import SwiftData
import Combine
import UIKit

struct PhotoCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var imuManager = IMUManager()
    @State private var saveStatusMessage: String?
    @State private var saveStatusIsError = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    cameraSection(in: geometry.size)
                    imuSection
                    captureButton
                    statusLabel
                    savedItemsLink
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Photo & IMU")
        .onAppear {
            imuManager.startUpdates()
        }
        .onDisappear {
            imuManager.stopUpdates()
            cameraManager.stopSession()
        }
        .onReceive(cameraManager.$latestCapture.compactMap { $0 }) { capture in
            saveCapture(capture)
        }
        .onReceive(cameraManager.$captureError.compactMap { $0 }) { message in
            showStatus(message: message, isError: true)
        }
    }

    private func cameraSection(in size: CGSize) -> some View {
        Group {
            if let cameraError = cameraManager.cameraError {
                Text(cameraError)
                    .multilineTextAlignment(.center)
                    .frame(height: previewHeight(for: size))
                    .padding(.horizontal)
            } else if cameraManager.isAuthorized && cameraManager.isSessionRunning {
                CameraView(session: cameraManager.session)
                    .frame(height: previewHeight(for: size))
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else if cameraManager.isAuthorized {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Starting camera...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(height: previewHeight(for: size))
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Text("Camera access is required")
                    .frame(height: previewHeight(for: size))
                    .padding(.horizontal)
            }
        }
    }

    private var imuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IMU Data")
                .font(.headline)
            if let motionError = imuManager.motionError {
                Text(motionError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accelerometer:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("X: \(imuManager.imuData.accelerometerX, specifier: "%.6f") m/s²")
                Text("Y: \(imuManager.imuData.accelerometerY, specifier: "%.6f") m/s²")
                Text("Z: \(imuManager.imuData.accelerometerZ, specifier: "%.6f") m/s²")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Gyroscope:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("X: \(imuManager.imuData.gyroscopeX, specifier: "%.6f") rad/s")
                Text("Y: \(imuManager.imuData.gyroscopeY, specifier: "%.6f") rad/s")
                Text("Z: \(imuManager.imuData.gyroscopeZ, specifier: "%.6f") rad/s")
            }
        }
        .padding(.horizontal)
    }

    private var captureButton: some View {
        Button(action: takePhoto) {
            HStack {
                if cameraManager.isCapturingPhoto {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "camera.fill")
                }
                Text(cameraManager.isCapturingPhoto ? "Capturing..." : "Take Photo")
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background((cameraManager.isSessionRunning && !cameraManager.isCapturingPhoto) ? Color.blue : Color.gray)
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .disabled(!cameraManager.isSessionRunning || cameraManager.isCapturingPhoto)
    }

    private var savedItemsLink: some View {
        NavigationLink {
            PhotoSavedItemsView()
        } label: {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text("View Saved Photos")
            }
            .font(.headline)
            .foregroundColor(.blue)
            .padding()
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    private var statusLabel: some View {
        Group {
            if let message = saveStatusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(saveStatusIsError ? .red : .green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
    }

    private func previewHeight(for size: CGSize) -> CGFloat {
        max(size.height * 0.45, 240)
    }

    private func takePhoto() {
        cameraManager.capturePhoto()
    }

    private func showStatus(message: String, isError: Bool = false) {
        withAnimation {
            saveStatusIsError = isError
            saveStatusMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if saveStatusMessage == message {
                withAnimation {
                    saveStatusMessage = nil
                }
            }
        }
    }

    private func saveCapture(_ capture: CameraCapture) {
        let imuData = imuManager.getCurrentData()

        withAnimation {
            let newItem = PhotoItem(
                timestamp: Date(),
                imageData: capture.data,
                photoMetadata: capture.metadata,
                accelerometerX: imuData.accelerometerX,
                accelerometerY: imuData.accelerometerY,
                accelerometerZ: imuData.accelerometerZ,
                gyroscopeX: imuData.gyroscopeX,
                gyroscopeY: imuData.gyroscopeY,
                gyroscopeZ: imuData.gyroscopeZ
            )
            modelContext.insert(newItem)
        }

        showStatus(message: "Photo and IMU data saved.")
    }
}

struct PhotoSavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PhotoItem.timestamp, order: .reverse) private var items: [PhotoItem]
    @State private var isExporting = false
    @State private var exportFolderURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    PhotoItemDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        if let imageData = item.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipped()
                                .cornerRadius(12)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                .font(.headline)
                            Text("Accel: x \(item.accelerometerX, specifier: "%.4f"), y \(item.accelerometerY, specifier: "%.4f"), z \(item.accelerometerZ, specifier: "%.4f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Gyro: x \(item.gyroscopeX, specifier: "%.4f"), y \(item.gyroscopeY, specifier: "%.4f"), z \(item.gyroscopeZ, specifier: "%.4f")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Saved Photos")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    exportItems()
                } label: {
                    if isPreparingExport {
                        ProgressView()
                    } else {
                        Text("Export")
                    }
                }
                .disabled(isPreparingExport)
            }
        }
        .sheet(isPresented: $isExporting, onDismiss: cleanupExport) {
            if let folderURL = exportFolderURL {
                DocumentExporterView(url: folderURL) {
                    isExporting = false
                }
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func deleteItems(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func exportItems() {
        guard !isPreparingExport else { return }
        isPreparingExport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let exporter = PhotoItemExportService()
                let result = try exporter.export(items: items)

                DispatchQueue.main.async {
                    exportFolderURL = result
                    isExporting = true
                    isPreparingExport = false
                }
            } catch {
                DispatchQueue.main.async {
                    exportErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isPreparingExport = false
                }
            }
        }
    }

    private func cleanupExport() {
        if let url = exportFolderURL {
            try? FileManager.default.removeItem(at: url)
            exportFolderURL = nil
        }
        isExporting = false
    }
}

struct PhotoItemDetailView: View {
    let item: PhotoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let imageData = item.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(10)
                } else {
                    Text("No photo available for this entry.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Timestamp")
                        .font(.headline)
                    Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        .font(.body)

                    Divider()

                    Text("Accelerometer Data")
                        .font(.headline)
                    Text("X: \(item.accelerometerX, specifier: "%.6f") m/s²")
                    Text("Y: \(item.accelerometerY, specifier: "%.6f") m/s²")
                    Text("Z: \(item.accelerometerZ, specifier: "%.6f") m/s²")

                    Divider()

                    Text("Gyroscope Data")
                        .font(.headline)
                    Text("X: \(item.gyroscopeX, specifier: "%.6f") rad/s")
                    Text("Y: \(item.gyroscopeY, specifier: "%.6f") rad/s")
                    Text("Z: \(item.gyroscopeZ, specifier: "%.6f") rad/s")
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("Photo Details")
    }
}

#Preview {
    PhotoCaptureView()
        .modelContainer(for: PhotoItem.self, inMemory: true)
}
