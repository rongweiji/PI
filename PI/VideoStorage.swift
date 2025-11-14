//
//  VideoStorage.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation

enum VideoStorage {
    private static let folderName = "VideoRecords"

    static func baseDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func urlForVideo(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func urlForIMUCSV(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func saveRecording(tempVideoURL: URL, samples: [IMUSample], timestamp: Date) throws -> (videoFilename: String, imuFilename: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "VID_\(formatter.string(from: timestamp))"

        let videoFilename = "\(baseName).mov"
        let imuFilename = "\(baseName)_imu.csv"

        let targetVideoURL = try urlForVideo(filename: videoFilename)
        let targetIMUURL = try urlForIMUCSV(filename: imuFilename)

        if FileManager.default.fileExists(atPath: targetVideoURL.path) {
            try FileManager.default.removeItem(at: targetVideoURL)
        }
        if FileManager.default.fileExists(atPath: targetIMUURL.path) {
            try FileManager.default.removeItem(at: targetIMUURL)
        }

        try FileManager.default.moveItem(at: tempVideoURL, to: targetVideoURL)

        let csv = makeIMUCSV(from: samples)
        try csv.write(to: targetIMUURL, atomically: true, encoding: .utf8)

        return (videoFilename, imuFilename)
    }

    static func deleteRecording(videoFilename: String, imuFilename: String) {
        if let videoURL = try? urlForVideo(filename: videoFilename) {
            try? FileManager.default.removeItem(at: videoURL)
        }
        if let imuURL = try? urlForIMUCSV(filename: imuFilename) {
            try? FileManager.default.removeItem(at: imuURL)
        }
    }

    private static func makeIMUCSV(from samples: [IMUSample]) -> String {
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
