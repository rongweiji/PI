//
//  IMUOnlyCaptureView.swift
//  PI
//
//  Created by Rongwei Ji on 11/24/25.
//

import SwiftUI
import SwiftData

private enum IMUSamplingRate: Double, CaseIterable, Identifiable {
    case thirty = 30
    case fifty = 50
    case hundred = 100

    var id: Double { rawValue }

    var displayName: String {
        "\(Int(rawValue)) Hz"
    }

    var interval: TimeInterval {
        1.0 / rawValue
    }
}

struct IMUOnlyCaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var imuManager = IMUManager()
    @State private var imuRecorder = IMUStreamRecorder()
    @State private var selectedSamplingRate: IMUSamplingRate = .thirty
    @State private var isRecording = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                liveIMUSection
                samplingRateSelector
                recordingControls
                statusLabel
                savedItemsLink
            }
            .padding(.vertical, 32)
        }
        .navigationTitle("IMU Only")
        .onAppear {
            imuManager.startUpdates()
            applySelectedSamplingRate()
        }
        .onDisappear {
            imuManager.stopUpdates()
            if isRecording {
                _ = imuRecorder.stop()
                isRecording = false
            }
        }
        .onChange(of: selectedSamplingRate) { _ in
            applySelectedSamplingRate()
        }
    }

    private var liveIMUSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live IMU Data")
                .font(.headline)
            if let error = imuManager.motionError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accelerometer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("X: \(imuManager.imuData.accelerometerX, specifier: "%.6f") m/s²")
                Text("Y: \(imuManager.imuData.accelerometerY, specifier: "%.6f") m/s²")
                Text("Z: \(imuManager.imuData.accelerometerZ, specifier: "%.6f") m/s²")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Gyroscope")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("X: \(imuManager.imuData.gyroscopeX, specifier: "%.6f") rad/s")
                Text("Y: \(imuManager.imuData.gyroscopeY, specifier: "%.6f") rad/s")
                Text("Z: \(imuManager.imuData.gyroscopeZ, specifier: "%.6f") rad/s")
            }
        }
        .padding(.horizontal)
    }

    private var samplingRateSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sampling Rate")
                .font(.headline)
            Picker("Sampling Rate", selection: $selectedSamplingRate) {
                ForEach(IMUSamplingRate.allCases) { rate in
                    Text(rate.displayName).tag(rate)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isRecording)
            if isRecording {
                Text("Stop recording to change sampling rate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    private var recordingControls: some View {
        HStack(spacing: 16) {
            Button {
                startRecording()
            } label: {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                    Text("Start")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isRecording ? Color.gray : Color.green)
                .cornerRadius(12)
            }
            .disabled(isRecording)

            Button {
                stopRecording()
            } label: {
                HStack {
                    Image(systemName: "stop.circle")
                    Text("Stop")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(isRecording ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!isRecording)
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
            IMUSessionSavedItemsView()
        } label: {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("View IMU Sessions")
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

    private func startRecording() {
        guard !isRecording else { return }
        imuRecorder.start()
        isRecording = true
        showStatus(message: "Recording IMU samples…", isError: false)
    }

    private func stopRecording() {
        guard isRecording else { return }
        let samples = imuRecorder.stop()
        isRecording = false

        guard !samples.isEmpty else {
            showStatus(message: "No IMU samples captured.", isError: true)
            return
        }

        saveSession(from: samples)
    }

    private func saveSession(from samples: [IMUSample]) {
        do {
            let timestamp = Date()
            let result = try IMUSessionStorage.save(samples: samples, timestamp: timestamp)
            let item = IMUSessionItem(
                timestamp: timestamp,
                duration: result.duration,
                sampleCount: result.sampleCount,
                imuCSVFilename: result.imuFilename,
                samplingRateHz: selectedSamplingRate.rawValue
            )
            modelContext.insert(item)
            showStatus(message: "IMU session saved.", isError: false)
        } catch {
            showStatus(message: "Failed to save IMU session: \(error.localizedDescription)", isError: true)
        }
    }

    private func applySelectedSamplingRate() {
        imuRecorder.setUpdateInterval(selectedSamplingRate.interval)
    }

    private func showStatus(message: String, isError: Bool) {
        withAnimation {
            statusMessage = message
            statusIsError = isError
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if statusMessage == message {
                withAnimation {
                    statusMessage = nil
                }
            }
        }
    }
}

struct IMUSessionSavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IMUSessionItem.timestamp, order: .reverse) private var items: [IMUSessionItem]
    @State private var isExporting = false
    @State private var exportFolderURL: URL?
    @State private var exportErrorMessage: String?
    @State private var isPreparingExport = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    IMUSessionDetailView(item: item)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                            .font(.headline)
                        Text("Duration: \(item.duration, format: .number.precision(.fractionLength(2))) s • Samples: \(item.sampleCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Rate: \(Int(item.samplingRateHz)) Hz")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .onDelete(perform: deleteItems)
        }
        .navigationTitle("IMU Sessions")
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
            if let url = exportFolderURL {
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
            IMUSessionStorage.deleteRecording(imuFilename: item.imuCSVFilename)
            modelContext.delete(item)
        }
    }

    private func exportItems() {
        guard !isPreparingExport else { return }
        isPreparingExport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let exporter = IMUSessionExportService()
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

struct IMUSessionDetailView: View {
    let item: IMUSessionItem

    var body: some View {
        List {
            Section("Timestamp") {
                Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
            }

            Section("Details") {
                Text("Duration: \(item.duration, format: .number.precision(.fractionLength(2))) seconds")
                Text("IMU Samples: \(item.sampleCount)")
                Text("Sampling Rate: \(Int(item.samplingRateHz)) Hz")
                Text("File: \(item.imuCSVFilename)")
            }
        }
        .navigationTitle("Session Details")
    }
}

#Preview {
    NavigationStack {
        IMUOnlyCaptureView()
            .environment(\.modelContext, try! ModelContainer(for: Schema([IMUSessionItem.self]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]).mainContext)
    }
}
