//
//  VideoARCaptureView.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import SwiftUI
import SwiftData
import AVKit
import Combine

#if canImport(ARKit)
import ARKit
import RealityKit

struct VideoARCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var captureManager = VideoARCaptureManager()
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showResolutionSheet = true
    @State private var pendingFormatSelection: ARVideoFormatOption?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                arPreview
                resolutionInfo
                parametersSection
                recordingControls
                statusLabel
                savedItemsLink
            }
            .padding(.vertical, 24)
        }
        .navigationTitle("Video + AR + IMU")
        .onAppear {
            captureManager.refreshAvailableFormats()
            pendingFormatSelection = captureManager.selectedFormat
            showResolutionSheet = true
        }
        .onChange(of: captureManager.availableFormats) { newValue in
            if pendingFormatSelection == nil {
                pendingFormatSelection = newValue.first
            }
        }
        .onDisappear {
            captureManager.stopSession()
        }
        .onReceive(captureManager.$latestRecording.compactMap { $0 }) { result in
            saveRecording(result)
        }
        .onReceive(captureManager.$captureError.compactMap { $0 }) { message in
            showStatus(message: message, isError: true)
        }
        .sheet(isPresented: $showResolutionSheet, onDismiss: {
            guard captureManager.isSessionRunning else { return }
        }) {
            ResolutionSheetContent(
                available: captureManager.availableFormats,
                selection: $pendingFormatSelection,
                onConfirm: {
                    let chosen = pendingFormatSelection ?? captureManager.availableFormats.first
                    captureManager.startSession(using: chosen)
                    showResolutionSheet = false
                },
                onCancel: {
                    showResolutionSheet = false
                }
            )
            .presentationDetents([.fraction(0.4), .medium])
        }
    }

    private var arPreview: some View {
        Group {
            if captureManager.isSessionRunning {
                ARPreviewView(session: captureManager.session)
                    .frame(height: 280)
                    .cornerRadius(12)
                    .padding(.horizontal)
            } else if let error = captureManager.captureError {
                Text(error)
                    .multilineTextAlignment(.center)
                    .frame(height: 280)
                    .padding(.horizontal)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Starting AR session...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    private var resolutionInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Video Resolution")
                .font(.headline)
            Text(captureManager.selectedFormat?.label ?? "Not set")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private var parametersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture Parameters")
                .font(.headline)
            parameterRow(label: "Video Resolution", value: captureManager.selectedFormat?.label ?? "Not set")
            parameterRow(label: "Video Frame Rate", value: "30 FPS")
            parameterRow(label: "Exposure", value: "0.01 s (fixed)")
            parameterRow(label: "IMU Sampling", value: "100 Hz")
            parameterRow(label: "AR Odometry", value: "100 Hz")
        }
        .padding(.horizontal)
    }

    private func parameterRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.footnote)
    }

    private var recordingControls: some View {
        HStack(spacing: 16) {
            Button {
                captureManager.startRecording()
                showStatus(message: "Recording...", isError: false)
            } label: {
                Label("Start", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(!captureManager.isRecording ? Color.red : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(captureManager.isRecording || !captureManager.isSessionRunning)

            Button {
                captureManager.stopRecording()
            } label: {
                Label("Stop", systemImage: "stop.circle")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(captureManager.isRecording ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!captureManager.isRecording)
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
            VideoARSavedItemsView()
        } label: {
            HStack {
                Image(systemName: "film.stack")
                Text("View Recorded Sessions")
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

    private func saveRecording(_ recording: VideoARCaptureResult) {
        do {
            let timestamp = Date()
            let result = try VideoARStorage.saveRecording(
                tempVideoURL: recording.videoURL,
                imuSamples: recording.imuSamples,
                arSamples: recording.arSamples,
                timestamp: timestamp
            )

            let item = VideoARItem(
                timestamp: timestamp,
                videoFilename: result.videoFilename,
                imuCSVFilename: result.imuFilename,
                arCSVFilename: result.arFilename,
                duration: recording.duration,
                imuSampleCount: result.imuCount,
                arSampleCount: result.arCount
            )
            modelContext.insert(item)
            showStatus(message: "Recording saved.", isError: false)
        } catch {
            showStatus(message: "Failed to save recording: \(error.localizedDescription)", isError: true)
        }
    }
}

private struct ARPreviewView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.session = session
        view.automaticallyConfigureSession = false
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

private struct ResolutionSheetContent: View {
    let available: [ARVideoFormatOption]
    @Binding var selection: ARVideoFormatOption?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(available) { option in
                HStack {
                    Text(option.label)
                    Spacer()
                    if selection == option {
                        Image(systemName: "checkmark")
                            .foregroundColor(.blue)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selection = option
                }
            }
            .navigationTitle("Select Resolution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue", action: onConfirm)
                        .disabled(selection == nil)
                }
            }
        }
    }
}

struct VideoARSavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoARItem.timestamp, order: .reverse) private var items: [VideoARItem]
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    VideoARItemDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.headline)
                        Text("Duration: \(item.duration, format: .number.precision(.fractionLength(1))) s • IMU: \(item.imuSampleCount) • AR: \(item.arSampleCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("AR Recordings")
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
                .disabled(isPreparingExport)
            }
        }
        .sheet(isPresented: $isExporting, onDismiss: cleanupExport) {
            if let url = exportURL {
                DocumentExporterView(url: url) {
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
            VideoARStorage.deleteRecording(
                videoFilename: item.videoFilename,
                imuFilename: item.imuCSVFilename,
                arFilename: item.arCSVFilename
            )
            modelContext.delete(item)
        }
    }

    private func exportItems() {
        guard !isPreparingExport else { return }
        isPreparingExport = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let exporter = VideoARItemExportService()
                let folder = try exporter.export(items: items)
                DispatchQueue.main.async {
                    exportURL = folder
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
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
            exportURL = nil
        }
        isExporting = false
    }
}

struct VideoARItemDetailView: View {
    let item: VideoARItem

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
                    Text("IMU Samples: \(item.imuSampleCount)")
                    Text("AR Samples: \(item.arSampleCount)")

                    Divider()

                    Text("Files")
                        .font(.headline)
                    Text("Video: \(item.videoFilename)")
                    Text("IMU CSV: \(item.imuCSVFilename)")
                    Text("AR CSV: \(item.arCSVFilename)")
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("AR Recording Details")
    }

    private func makePlayer() -> AVPlayer? {
        guard let url = try? VideoARStorage.urlForVideo(filename: item.videoFilename) else { return nil }
        return AVPlayer(url: url)
    }
}

#else

struct VideoARCaptureView: View {
    var body: some View {
        Text("ARKit is not supported on this platform.")
            .padding()
    }
}

#endif
