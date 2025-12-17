//
//  VideoOnlyStorage.swift
//  PI
//
//  Created by Rongwei Ji on 12/16/25.
//

import Foundation

enum VideoOnlyStorage {
    private static let folderName = "VideoOnlyRecords"

    private static func baseDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = documents.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func saveVideo(tempURL: URL, timestamp: Date) throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "VIDONLY_\(formatter.string(from: timestamp)).mov"
        let targetURL = try baseDirectory().appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
        return filename
    }

    static func urlForVideo(filename: String) throws -> URL {
        try baseDirectory().appendingPathComponent(filename)
    }

    static func deleteVideo(filename: String) {
        if let url = try? urlForVideo(filename: filename) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
