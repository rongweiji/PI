//
//  IMUStreamRecorder.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation
import CoreMotion

final class IMUStreamRecorder {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private(set) var samples: [IMUSample] = []
    private(set) var isRecording = false
    private var bootTimeReference: Date?
    private var updateInterval: TimeInterval {
        didSet {
            motionManager.deviceMotionUpdateInterval = updateInterval
        }
    }

    init(updateInterval: TimeInterval = 1.0 / 30.0) {
        self.updateInterval = updateInterval
        motionManager.deviceMotionUpdateInterval = updateInterval
        queue.name = "IMUStreamRecorderQueue"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !isRecording else { return }
        samples = []
        isRecording = true
        bootTimeReference = Date(timeIntervalSinceNow: -ProcessInfo.processInfo.systemUptime)

        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let timestampDate: Date
            if let bootTimeReference {
                timestampDate = bootTimeReference.addingTimeInterval(motion.timestamp)
            } else {
                timestampDate = Date()
            }
            let sample = IMUSample(
                timestamp: timestampDate,
                accelerationX: motion.userAcceleration.x,
                accelerationY: motion.userAcceleration.y,
                accelerationZ: motion.userAcceleration.z,
                rotationX: motion.rotationRate.x,
                rotationY: motion.rotationRate.y,
                rotationZ: motion.rotationRate.z
            )
            self.samples.append(sample)
        }
    }

    func stop() -> [IMUSample] {
        guard isRecording else { return samples }
        motionManager.stopDeviceMotionUpdates()
        isRecording = false
        bootTimeReference = nil
        return samples
    }

    func setUpdateInterval(_ interval: TimeInterval) {
        guard !isRecording else { return }
        updateInterval = interval
    }
}
