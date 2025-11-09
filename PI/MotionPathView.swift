import SwiftUI
import Combine
import CoreMotion
import simd

final class MotionPathTracker: ObservableObject {
    @Published private(set) var positions: [CGPoint] = [.zero]
    @Published private(set) var distanceFromStart: Double = 0
    @Published private(set) var isCalibrating = false
    @Published var isTracking = false
    @Published var motionError: String?
    @Published var integrationSpeedThreshold: Double = 0.02

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var lastTimestamp: TimeInterval?
    private var velocity = SIMD2<Double>(repeating: 0)
    private var currentPosition = SIMD2<Double>(repeating: 0)
    private var bias = SIMD2<Double>(repeating: 0)
    private var calibrationAccumulator = SIMD2<Double>(repeating: 0)
    private var calibrationSampleCount = 0
    private var zeroVelocitySampleCount = 0

    private let calibrationSampleTarget = 90
    private let minimumAccelerationMagnitude = 0.02
    private let velocityDamping = 0.985
    private let zeroVelocityAccelThreshold = 0.015
    private let zeroVelocityGyroThreshold = 0.01
    private let zeroVelocitySampleTarget = 12
    private let gravityConstant = 9.80665

    init() {
        queue.name = "MotionPathTracker.queue"
        queue.maxConcurrentOperationCount = 1
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
    }

    func start() {
        guard !isTracking else { return }

        motionError = nil
        prepareForCalibration(resetPosition: false)

        #if targetEnvironment(simulator)
        motionError = "Motion sensors are not available in the simulator."
        return
        #endif

        guard motionManager.isDeviceMotionAvailable else {
            motionError = "Device motion is not available on this device."
            return
        }

        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else { return }
            self.handle(deviceMotion: data)
        }

        isTracking = true
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isTracking = false
        lastTimestamp = nil
        isCalibrating = false
    }

    func resetPath() {
        DispatchQueue.main.async {
            self.positions = [.zero]
            self.distanceFromStart = 0
        }
        prepareForCalibration(resetPosition: true, shouldCalibrate: isTracking)
    }

    private func handle(deviceMotion: CMDeviceMotion) {
        let timestamp = deviceMotion.timestamp

        guard let lastTimestamp else {
            self.lastTimestamp = timestamp
            return
        }

        let deltaTime = timestamp - lastTimestamp
        self.lastTimestamp = timestamp

        let horizontalAcceleration = transformedHorizontalAcceleration(from: deviceMotion)

        if isCalibrating {
            calibrationAccumulator += horizontalAcceleration
            calibrationSampleCount += 1
            if calibrationSampleCount >= calibrationSampleTarget {
                let newBias = calibrationAccumulator / Double(calibrationSampleCount)
                DispatchQueue.main.async {
                    self.bias = newBias
                    self.isCalibrating = false
                }
            }
            return
        }

        var correctedAcceleration = horizontalAcceleration - bias
        if simd_length(correctedAcceleration) < minimumAccelerationMagnitude {
            correctedAcceleration = .zero
        }

        let gyroVector = SIMD3<Double>(deviceMotion.rotationRate.x, deviceMotion.rotationRate.y, deviceMotion.rotationRate.z)
        let gyroMagnitude = simd_length(gyroVector)

        if simd_length(correctedAcceleration) < zeroVelocityAccelThreshold && gyroMagnitude < zeroVelocityGyroThreshold {
            zeroVelocitySampleCount += 1
        } else {
            zeroVelocitySampleCount = 0
        }

        let previousVelocity = velocity
        var updatedVelocity = previousVelocity * velocityDamping

        if zeroVelocitySampleCount >= zeroVelocitySampleTarget {
            updatedVelocity = .zero
        } else {
            updatedVelocity += correctedAcceleration * deltaTime
        }

        let averageVelocity = (previousVelocity + updatedVelocity) * 0.5
        let averageSpeed = simd_length(averageVelocity)
        if averageSpeed >= integrationSpeedThreshold {
            currentPosition += averageVelocity * deltaTime
        }
        velocity = updatedVelocity

        let pathPoint = CGPoint(x: currentPosition.x, y: currentPosition.y)
        let distance = hypot(currentPosition.x, currentPosition.y)

        DispatchQueue.main.async {
            self.positions.append(pathPoint)
            if self.positions.count > 2000 {
                self.positions.removeFirst(self.positions.count - 2000)
            }
            self.distanceFromStart = distance
        }
    }

    private func prepareForCalibration(resetPosition: Bool, shouldCalibrate: Bool = true) {
        if resetPosition {
            currentPosition = .zero
        }
        velocity = .zero
        bias = .zero
        calibrationAccumulator = .zero
        calibrationSampleCount = 0
        lastTimestamp = nil
        zeroVelocitySampleCount = 0
        isCalibrating = shouldCalibrate
    }

    private func transformedHorizontalAcceleration(from motion: CMDeviceMotion) -> SIMD2<Double> {
        let accel = motion.userAcceleration
        let deviceVector = SIMD3<Double>(accel.x, accel.y, accel.z) * gravityConstant
        let quat = motion.attitude.quaternion
        let rotation = simd_quatd(ix: quat.x, iy: quat.y, iz: quat.z, r: quat.w)
        let worldVector = rotation.inverse.act(deviceVector)
        return SIMD2<Double>(worldVector.x, worldVector.y)
    }
}

struct MotionPathView: View {
    @StateObject private var tracker = MotionPathTracker()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Realtime Motion Path")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Place the iPhone on a flat surface and move it to visualize its path in realtime.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if tracker.isCalibrating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Calibrating… keep the device still")
                            .font(.footnote)
                    }
                    .padding(.top, 4)
                }
                if let error = tracker.motionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }

            pathCanvas
                .frame(height: 320)

            integrationThresholdControl

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
                    Label(tracker.isTracking ? "Pause" : "Start", systemImage: tracker.isTracking ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(tracker.isTracking ? Color.orange : Color.green)
                        .cornerRadius(14)
                }
                .disabled(tracker.isCalibrating)

                Button(action: tracker.resetPath) {
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
        .navigationTitle("Motion Path")
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
    }

    private var pathCanvas: some View {
        GeometryReader { _ in
            Canvas { context, size in
                let samples = tracker.positions
                guard samples.count > 1 else { return }

                let scaledPoints = scale(samples: samples, in: size)
                var path = Path()
                path.addLines(scaledPoints)

                context.stroke(path, with: .color(.blue), lineWidth: 3)

                if let last = scaledPoints.last {
                    let markerSize: CGFloat = 12
                    let markerRect = CGRect(x: last.x - markerSize / 2, y: last.y - markerSize / 2, width: markerSize, height: markerSize)
                    context.fill(Path(ellipseIn: markerRect), with: .color(.red))
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

    private var integrationThresholdControl: some View {
        let thresholdBinding = Binding<Double>(
            get: { tracker.integrationSpeedThreshold },
            set: { tracker.integrationSpeedThreshold = $0 }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Integration speed threshold")
                    .font(.headline)
                Spacer()
                Text("\(tracker.integrationSpeedThreshold, specifier: "%.3f") m/s")
                    .monospacedDigit()
                    .font(.subheadline)
            }
            Slider(value: thresholdBinding, in: 0...0.2, step: 0.005)
            Text("Only integrate when estimated speed exceeds this value. Raise it to ignore tiny motions or lower it to capture gentle drifts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
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
        if tracker.isTracking {
            tracker.stop()
        } else {
            tracker.start()
        }
    }
}

#Preview {
    NavigationStack {
        MotionPathView()
    }
}
