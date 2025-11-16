//
//  VideoARStorage.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation

enum VideoARStorage {
    private static let folderName = "VideoARRecords"

    private static func baseDirectory() throws -> URL {
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

    static func urlForARCSV(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func saveRecording(tempVideoURL: URL, imuSamples: [IMUSample], arSamples: [ARPoseSample], timestamp: Date) throws -> (videoFilename: String, imuFilename: String, arFilename: String, duration: TimeInterval, imuCount: Int, arCount: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "ARVID_\(formatter.string(from: timestamp))"

        let videoFilename = "\(baseName).mov"
        let imuFilename = "\(baseName)_imu.csv"
        let arFilename = "\(baseName)_ar.csv"

        let targetVideoURL = try urlForVideo(filename: videoFilename)
        let targetIMUURL = try urlForIMUCSV(filename: imuFilename)
        let targetARURL = try urlForARCSV(filename: arFilename)

        for url in [targetVideoURL, targetIMUURL, targetARURL] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }

        try FileManager.default.moveItem(at: tempVideoURL, to: targetVideoURL)

        let imuCSV = makeIMUCSV(from: imuSamples)
        try imuCSV.write(to: targetIMUURL, atomically: true, encoding: .utf8)

        let arCSV = makeARCSV(from: arSamples)
        try arCSV.write(to: targetARURL, atomically: true, encoding: .utf8)

        let duration: TimeInterval
        if let first = imuSamples.first?.timestamp, let last = imuSamples.last?.timestamp, imuSamples.count > 1 {
            duration = last.timeIntervalSince(first)
        } else {
            duration = 0
        }

        return (videoFilename, imuFilename, arFilename, duration, imuSamples.count, arSamples.count)
    }

    static func deleteRecording(videoFilename: String, imuFilename: String, arFilename: String) {
        let files = [try? urlForVideo(filename: videoFilename),
                     try? urlForIMUCSV(filename: imuFilename),
                     try? urlForARCSV(filename: arFilename)]
        for url in files.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
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

    private static func makeARCSV(from samples: [ARPoseSample]) -> String {
        var lines = ["timestamp_ref,posX,posY,posZ,orientX,orientY,orientZ,orientW"]
        for sample in samples {
            let line = [
                String(format: "%.9f", sample.timestamp.timeIntervalSinceReferenceDate),
                String(format: "%.6f", sample.positionX),
                String(format: "%.6f", sample.positionY),
                String(format: "%.6f", sample.positionZ),
                String(format: "%.6f", sample.orientationX),
                String(format: "%.6f", sample.orientationY),
                String(format: "%.6f", sample.orientationZ),
                String(format: "%.6f", sample.orientationW)
            ].joined(separator: ",")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
