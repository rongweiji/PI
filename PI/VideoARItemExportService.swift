//
//  VideoARItemExportService.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation

enum VideoARItemExportError: LocalizedError {
    case noItems
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "There are no AR captures to export."
        case .missingFile(let name):
            return "Missing file for export: \(name)"
        }
    }
}

struct VideoARItemExportService {
    private let fileManager = FileManager.default

    func export(items: [VideoARItem]) throws -> URL {
        guard !items.isEmpty else { throw VideoARItemExportError.noItems }
        let exportFolder = try createExportFolder()

        for (index, item) in items.enumerated() {
            let identifier = String(format: "%04d", index + 1)

            let framesSource = try VideoARStorage.urlForFramesZip(filename: item.framesZipFilename)
            let timestampsSource = try VideoARStorage.urlForTimestamps(filename: item.timestampsFilename)
            let poseSource = try VideoARStorage.urlForPoseCSV(filename: item.poseCSVFilename)

            guard fileManager.fileExists(atPath: framesSource.path) else {
                throw VideoARItemExportError.missingFile(item.framesZipFilename)
            }
            guard fileManager.fileExists(atPath: timestampsSource.path) else {
                throw VideoARItemExportError.missingFile(item.timestampsFilename)
            }
            guard fileManager.fileExists(atPath: poseSource.path) else {
                throw VideoARItemExportError.missingFile(item.poseCSVFilename)
            }

            let framesTarget = exportFolder.appendingPathComponent("\(identifier)_frames.zip")
            let timestampsTarget = exportFolder.appendingPathComponent("\(identifier)_timestamps.txt")
            let poseTarget = exportFolder.appendingPathComponent("\(identifier)_pose.csv")

            try fileManager.copyItem(at: framesSource, to: framesTarget)
            try fileManager.copyItem(at: timestampsSource, to: timestampsTarget)
            try fileManager.copyItem(at: poseSource, to: poseTarget)
        }

        return exportFolder
    }

    private func createExportFolder() throws -> URL {
        let base = fileManager.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderURL = base.appendingPathComponent("ARCaptureExport-\(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
