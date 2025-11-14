//
//  IMUSessionStorage.swift
//  PI
//
//  Created by Rongwei Ji on 11/24/25.
//

import Foundation

enum IMUSessionStorage {
    private static let folderName = "IMUSessions"

    private static func baseDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func urlForIMUCSV(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func save(samples: [IMUSample], timestamp: Date) throws -> (imuFilename: String, duration: TimeInterval, sampleCount: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "IMU_\(formatter.string(from: timestamp))"

        let imuFilename = "\(baseName).csv"
        let targetURL = try urlForIMUCSV(filename: imuFilename)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        let csvContent = makeCSV(from: samples)
        try csvContent.write(to: targetURL, atomically: true, encoding: .utf8)

        let duration: TimeInterval
        if let first = samples.first, let last = samples.last, samples.count > 1 {
            duration = last.timestamp.timeIntervalSince(first.timestamp)
        } else {
            duration = 0
        }

        return (imuFilename, duration, samples.count)
    }

    static func deleteRecording(imuFilename: String) {
        if let url = try? urlForIMUCSV(filename: imuFilename) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func makeCSV(from samples: [IMUSample]) -> String {
        var lines = ["timestamp_ref,accelX,accelY,accelZ,gyroX,gyroY,gyroZ"]
        for sample in samples {
            let line = [
                String(format: "%.9f", sample.timestamp.timeIntervalSinceReferenceDate),
                String(format: "%.6f", sample.accelerationX),
                String(format: "%.6f", sample.accelerationY),
                String(format: "%.6f", sample.accelerationZ),
                String(format: "%.6f", sample.rotationX),
                String(format: "%.6f", sample.rotationY),
                String(format: "%.6f", sample.rotationZ)
            ].joined(separator: ",")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
