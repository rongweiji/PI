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

    init(updateInterval: TimeInterval = 0.05) {
        motionManager.deviceMotionUpdateInterval = updateInterval
        queue.name = "IMUStreamRecorderQueue"
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable, !isRecording else { return }
        samples = []
        isRecording = true

        motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            let sample = IMUSample(
                timestamp: Date(),
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
        return samples
    }
}
