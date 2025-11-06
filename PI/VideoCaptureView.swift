//
//  VideoCaptureView.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import SwiftUI
import SwiftData
import AVKit
import Combine

struct VideoCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var videoManager = VideoCaptureManager()
    @StateObject private var imuManager = IMUManager()
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                cameraPreview
                imuSection
                recordingControls
                statusLabel
                savedItemsLink
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Video & IMU")
        .onAppear {
            imuManager.startUpdates()
        }
        .onDisappear {
            imuManager.stopUpdates()
            videoManager.stopSession()
        }
        .onReceive(videoManager.$latestRecording.compactMap { $0 }) { result in
            saveRecording(result)
        }
        .onReceive(videoManager.$captureError.compactMap { $0 }) { message in
            showStatus(message: message, isError: true)
        }
    }

    private var cameraPreview: some View {
        Group {
            if let cameraError = videoManager.cameraError {
                Text(cameraError)
                    .multilineTextAlignment(.center)
                    .frame(height: 280)
                    .padding(.horizontal)
            } else if videoManager.isAuthorized && videoManager.isSessionRunning {
                CameraView(session: videoManager.session)
                    .frame(height: 280)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else if videoManager.isAuthorized {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Starting camera...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Text("Camera access is required")
                    .frame(height: 280)
                    .padding(.horizontal)
            }
        }
    }

    private var imuSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live IMU Data")
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

    private var recordingControls: some View {
        HStack(spacing: 16) {
            Button {
                videoManager.startRecording()
                showStatus(message: "Recording video...", isError: false)
            } label: {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(videoManager.isSessionRunning && !videoManager.isRecording ? Color.red : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!videoManager.isSessionRunning || videoManager.isRecording)

            Button {
                videoManager.stopRecording()
            } label: {
                HStack {
                    Image(systemName: "stop.circle")
                    Text("Stop")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(videoManager.isRecording ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!videoManager.isRecording)
        }
        .padding(.horizontal)
    }

    private var statusLabel: some View {
        Group {
            if let message = statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(statusIsError ? .red : .green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
    }

    private var savedItemsLink: some View {
        NavigationLink {
            VideoSavedItemsView()
        } label: {
            HStack {
                Image(systemName: "film.stack")
                Text("View Recorded Videos")
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

    private func showStatus(message: String, isError: Bool) {
        withAnimation {
            statusIsError = isError
            statusMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if statusMessage == message {
                withAnimation {
                    statusMessage = nil
                }
            }
        }
    }

    private func saveRecording(_ recording: VideoCaptureResult) {
        do {
            let timestamp = Date()
            let result = try VideoStorage.saveRecording(
                tempVideoURL: recording.videoURL,
                samples: recording.imuSamples,
                timestamp: timestamp
            )

            let item = VideoItem(
                timestamp: timestamp,
                videoFilename: result.videoFilename,
                imuCSVFilename: result.imuFilename,
                duration: recording.duration,
                sampleCount: recording.imuSamples.count
            )

            modelContext.insert(item)
            showStatus(message: "Video and IMU data saved.", isError: false)
        } catch {
            showStatus(message: "Failed to save video: \(error.localizedDescription)", isError: true)
        }
    }
}

struct VideoSavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoItem.timestamp, order: .reverse) private var items: [VideoItem]
    @State private var isExporting = false
    @State private var exportFolderURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    VideoItemDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.headline)
                        Text("Duration: \(item.duration, format: .number.precision(.fractionLength(1))) s • Samples: \(item.sampleCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Recorded Videos")
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
            let item = items[index]
            VideoStorage.deleteRecording(videoFilename: item.videoFilename, imuFilename: item.imuCSVFilename)
            modelContext.delete(item)
        }
    }

    private func exportItems() {
        guard !isPreparingExport else { return }
        isPreparingExport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let exporter = VideoItemExportService()
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

struct VideoItemDetailView: View {
    let item: VideoItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let player = makePlayer() {
                    VideoPlayer(player: player)
                        .frame(height: 240)
                        .cornerRadius(12)
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    Text("Video file not available.")
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

                    Text("Details")
                        .font(.headline)
                    Text("Duration: \(item.duration, format: .number.precision(.fractionLength(1))) seconds")
                    Text("IMU Samples: \(item.sampleCount)")

                    Divider()

                    Text("Files")
                        .font(.headline)
                    Text("Video: \(item.videoFilename)")
                    Text("IMU CSV: \(item.imuCSVFilename)")
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("Video Details")
    }

    private func makePlayer() -> AVPlayer? {
        guard let url = try? VideoStorage.urlForVideo(filename: item.videoFilename) else { return nil }
        return AVPlayer(url: url)
    }
}

#Preview {
    NavigationStack {
        VideoCaptureView()
            .environment(\.modelContext, try! ModelContainer(for: Schema([PhotoItem.self, VideoItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]).mainContext)
    }
}
