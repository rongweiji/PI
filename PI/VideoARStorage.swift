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

    static func urlForFramesZip(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func urlForTimestamps(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func urlForPoseCSV(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func saveRecording(framesZipURL: URL,
                              timestampsURL: URL,
                              poseCSVURL: URL,
                              timestamp: Date,
                              duration: TimeInterval,
                              frameCount: Int) throws -> (framesZipFilename: String, timestampsFilename: String, poseFilename: String, duration: TimeInterval, frameCount: Int) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "ARFRAMES_\(formatter.string(from: timestamp))"

        let framesZipFilename = "\(baseName)_frames.zip"
        let timestampsFilename = "\(baseName)_timestamps.txt"
        let poseFilename = "\(baseName)_pose.csv"

        let targetFramesZipURL = try urlForFramesZip(filename: framesZipFilename)
        let targetTimestampsURL = try urlForTimestamps(filename: timestampsFilename)
        let targetPoseURL = try urlForPoseCSV(filename: poseFilename)

        for url in [targetFramesZipURL, targetTimestampsURL, targetPoseURL] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }

        try FileManager.default.moveItem(at: framesZipURL, to: targetFramesZipURL)
        try FileManager.default.moveItem(at: timestampsURL, to: targetTimestampsURL)
        try FileManager.default.moveItem(at: poseCSVURL, to: targetPoseURL)

        let tempFolder = framesZipURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: tempFolder)

        return (framesZipFilename, timestampsFilename, poseFilename, duration, frameCount)
    }

    static func deleteRecording(framesZipFilename: String, timestampsFilename: String, poseFilename: String) {
        let files = [try? urlForFramesZip(filename: framesZipFilename),
                     try? urlForTimestamps(filename: timestampsFilename),
                     try? urlForPoseCSV(filename: poseFilename)]
        for url in files.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
