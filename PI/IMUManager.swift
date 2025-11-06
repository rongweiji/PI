//
//  IMUManager.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation
import CoreMotion
import Combine

struct IMUData {
    var accelerometerX: Double = 0.0
    var accelerometerY: Double = 0.0
    var accelerometerZ: Double = 0.0
    var gyroscopeX: Double = 0.0
    var gyroscopeY: Double = 0.0
    var gyroscopeZ: Double = 0.0
}

class IMUManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var imuData = IMUData()
    @Published var isActive = false
    @Published var motionError: String?

    init() {
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.gyroUpdateInterval = 0.1
    }

    func startUpdates() {
        guard !isActive else { return }

        motionError = nil

        #if targetEnvironment(simulator)
        motionError = "Motion sensors are not available in the simulator."
        return
        #endif

        if motionManager.isAccelerometerAvailable {
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.imuData.accelerometerX = data.acceleration.x
                self?.imuData.accelerometerY = data.acceleration.y
                self?.imuData.accelerometerZ = data.acceleration.z
            }
        } else {
            motionError = "Accelerometer is not available on this device."
        }

        if motionManager.isGyroAvailable {
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.imuData.gyroscopeX = data.rotationRate.x
                self?.imuData.gyroscopeY = data.rotationRate.y
                self?.imuData.gyroscopeZ = data.rotationRate.z
            }
        } else {
            motionError = "Gyroscope is not available on this device."
        }

        isActive = true
    }

    func stopUpdates() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        isActive = false
    }

    func getCurrentData() -> IMUData {
        return imuData
    }
}
