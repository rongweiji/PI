//
//  VideoOnlyCaptureView.swift
//  PI
//
//  Created by Rongwei Ji on 12/16/25.
//

import SwiftUI
import SwiftData
import AVKit
import Combine

struct VideoOnlyCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var manager = VideoOnlyCaptureManager()
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                previewSection
                resolutionPicker
                recordingControls
                statusLabel
                savedItemsLink
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Video Only")
        .onAppear {
            manager.updateResolution(to: manager.selectedResolution)
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }
        .onDisappear {
            manager.stopSession()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(manager.$latestRecording.compactMap { $0 }) { recording in
            saveRecording(recording)
        }
        .onReceive(manager.$captureError.compactMap { $0 }) { message in
            showStatus(message: message, isError: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation != .unknown {
                deviceOrientation = orientation
            }
        }
    }

    private var previewSection: some View {
        GeometryReader { geometry in
            let dims = manager.selectedResolution.dimensions
            let isPortrait = deviceOrientation != .landscapeLeft && deviceOrientation != .landscapeRight
            let aspect = isPortrait
                ? CGFloat(dims.width) / CGFloat(dims.height)
                : CGFloat(dims.height) / CGFloat(dims.width)
            let height = geometry.size.width * aspect

            Group {
                if let cameraError = manager.cameraError {
                    Text(cameraError)
                        .multilineTextAlignment(.center)
                        .frame(height: height)
                        .padding(.horizontal)
                } else if manager.isAuthorized && manager.isSessionRunning {
                    CameraView(session: manager.session)
                        .frame(height: height)
                        .clipped()
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else if manager.isAuthorized {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Starting camera...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    Text("Camera access is required")
                        .frame(height: height)
                        .padding(.horizontal)
                }
            }
        }
        .frame(height: {
            let dims = manager.selectedResolution.dimensions
            let isPortrait = deviceOrientation != .landscapeLeft && deviceOrientation != .landscapeRight
            let aspect = isPortrait
                ? CGFloat(dims.width) / CGFloat(dims.height)
                : CGFloat(dims.height) / CGFloat(dims.width)
            return UIScreen.main.bounds.width * aspect
        }())
    }

    private var resolutionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video Resolution")
                .font(.headline)
            Picker("Resolution", selection: $manager.selectedResolution) {
                ForEach(VideoOnlyResolution.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: manager.selectedResolution) { newValue in
                manager.updateResolution(to: newValue)
            }
            Text("30 FPS fixed. Preview matches the selected video frame size.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var recordingControls: some View {
        HStack(spacing: 16) {
            Button {
                manager.startRecording()
                showStatus(message: "Recording...", isError: false)
            } label: {
                Label("Start", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(manager.isSessionRunning && !manager.isRecording ? Color.red : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!manager.isSessionRunning || manager.isRecording)

            Button {
                manager.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(manager.isRecording ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!manager.isRecording)
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
            }
        }
        .padding(.horizontal)
    }

    private var savedItemsLink: some View {
        NavigationLink {
            VideoOnlySavedItemsView()
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

    private func saveRecording(_ recording: (url: URL, duration: TimeInterval)) {
        do {
            let timestamp = Date()
            let filename = try VideoOnlyStorage.saveVideo(tempURL: recording.url, timestamp: timestamp)
            let item = VideoOnlyItem(
                timestamp: timestamp,
                videoFilename: filename,
                duration: recording.duration,
                resolutionLabel: manager.selectedResolution.label
            )
            modelContext.insert(item)
            showStatus(message: "Recording saved.", isError: false)
        } catch {
            showStatus(message: "Failed to save recording: \(error.localizedDescription)", isError: true)
        }
    }
}

struct VideoOnlySavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoOnlyItem.timestamp, order: .reverse) private var items: [VideoOnlyItem]
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false
    @State private var cleanupURL: URL?

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    VideoOnlyItemDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.headline)
                        Text("\(item.resolutionLabel) • \(item.duration, format: .number.precision(.fractionLength(1))) s")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("Videos")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
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
                .disabled(isPreparingExport || items.isEmpty)
            }
        }
        .sheet(isPresented: $isExporting, onDismiss: cleanupExport) {
            if let url = exportURL {
                DocumentExporterView(url: url) {
                    isExporting = false
                    cleanupExport()
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
            VideoOnlyStorage.deleteVideo(filename: item.videoFilename)
            modelContext.delete(item)
        }
    }

    private func exportItems() {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let exporter = VideoOnlyItemExportService()
                let folder = try exporter.export(items: items)
                DispatchQueue.main.async {
                    exportURL = folder
                    cleanupURL = folder
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
        if let url = cleanupURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
        cleanupURL = nil
        isExporting = false
    }
}

struct VideoOnlyItemDetailView: View {
    let item: VideoOnlyItem

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

                    Divider()

                    Text("Details")
                        .font(.headline)
                    Text("Duration: \(item.duration, format: .number.precision(.fractionLength(1))) s")
                    Text("Resolution: \(item.resolutionLabel)")

                    Divider()

                    Text("File")
                        .font(.headline)
                    Text("Video: \(item.videoFilename)")
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("Video Details")
    }

    private func makePlayer() -> AVPlayer? {
        guard let url = try? VideoOnlyStorage.urlForVideo(filename: item.videoFilename) else { return nil }
        return AVPlayer(url: url)
    }
}

#Preview {
    VideoOnlyCaptureView()
}
