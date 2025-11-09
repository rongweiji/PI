#if canImport(ARKit)

import SwiftUI
import Combine
import ARKit
import simd

final class ARMotionPathTracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var points: [CGPoint] = [.zero]
    @Published private(set) var distanceFromStart: Double = 0
    @Published var statusMessage: String?
    @Published var isRunning = false

    private let session = ARSession()
    private var referenceTransform: simd_float4x4?

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else {
            statusMessage = "ARKit world tracking is not supported on this device."
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        resetPath(keepSession: true)
        statusMessage = "Move the device to trace its path."
        isRunning = true
    }

    func pause() {
        session.pause()
        isRunning = false
        statusMessage = "Tracking paused."
    }

    func resetPath(keepSession: Bool) {
        if !keepSession {
            session.pause()
            isRunning = false
        }

        referenceTransform = nil
        DispatchQueue.main.async {
            self.points = [.zero]
            self.distanceFromStart = 0
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }

        let cameraTransform = frame.camera.transform

        if referenceTransform == nil {
            referenceTransform = cameraTransform
            return
        }

        guard let reference = referenceTransform else { return }
        let relativeTransform = simd_mul(simd_inverse(reference), cameraTransform)
        let translation = SIMD3(relativeTransform.columns.3.x, relativeTransform.columns.3.y, relativeTransform.columns.3.z)
        let horizontalPoint = CGPoint(x: Double(translation.x), y: Double(-translation.z))
        let horizontalDistance = hypot(translation.x, translation.z)

        DispatchQueue.main.async {
            self.points.append(horizontalPoint)
            if self.points.count > 2000 {
                self.points.removeFirst(self.points.count - 2000)
            }
            self.distanceFromStart = Double(horizontalDistance)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = error.localizedDescription
            self.isRunning = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Tracking interrupted."
            self.isRunning = false
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusMessage = "Tracking resumed."
            self.start()
        }
    }
}

struct ARMotionPathView: View {
    @StateObject private var tracker = ARMotionPathTracker()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("AR Motion Path")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Uses ARKit world tracking to draw your device path in realtime.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let status = tracker.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                }
            }

            pathCanvas
                .frame(height: 320)

            VStack(spacing: 4) {
                Text("Distance from start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(tracker.distanceFromStart, specifier: "%.02f") meters")
                    .font(.title2)
                    .monospacedDigit()
            }

            HStack(spacing: 16) {
                Button(action: toggleTracking) {
                    Label(tracker.isRunning ? "Pause" : "Start", systemImage: tracker.isRunning ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tracker.isRunning ? Color.orange : Color.green)
                        .cornerRadius(14)
                }

                Button {
                    tracker.resetPath(keepSession: tracker.isRunning)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .onAppear { tracker.start() }
        .onDisappear { tracker.pause() }
        .navigationTitle("AR Motion Path")
    }

    private var pathCanvas: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let samples = tracker.points
                guard samples.count > 1 else { return }

                let scaledPoints = scale(samples: samples, in: size)
                var path = Path()
                path.addLines(scaledPoints)

                context.stroke(path, with: .color(.purple), lineWidth: 3)

                if let last = scaledPoints.last {
                    let markerSize: CGFloat = 12
                    let markerRect = CGRect(x: last.x - markerSize / 2, y: last.y - markerSize / 2, width: markerSize, height: markerSize)
                    context.fill(Path(ellipseIn: markerRect), with: .color(.pink))
                }

                let centerIndicator = Path(ellipseIn: CGRect(x: size.width / 2 - 4, y: size.height / 2 - 4, width: 8, height: 8))
                context.fill(centerIndicator, with: .color(.gray))
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func scale(samples: [CGPoint], in size: CGSize) -> [CGPoint] {
        guard let minX = samples.map({ $0.x }).min(),
              let maxX = samples.map({ $0.x }).max(),
              let minY = samples.map({ $0.y }).min(),
              let maxY = samples.map({ $0.y }).max() else {
            return samples
        }

        let spanX = max(maxX - minX, 0.05)
        let spanY = max(maxY - minY, 0.05)
        let scale = 0.8 * min(size.width / spanX, size.height / spanY)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2

        return samples.map { point in
            let shiftedX = (point.x - centerX) * scale + size.width / 2
            let shiftedY = (point.y - centerY) * scale + size.height / 2
            return CGPoint(x: shiftedX, y: shiftedY)
        }
    }

    private func toggleTracking() {
        if tracker.isRunning {
            tracker.pause()
        } else {
            tracker.start()
        }
    }
}

#Preview {
    NavigationStack {
        ARMotionPathView()
    }
}

#else

import SwiftUI

struct ARMotionPathView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arkit")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("ARKit tracking is not supported on this platform.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .navigationTitle("AR Motion Path")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
