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
            return "There are no AR recordings to export."
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

            let videoSource = try VideoARStorage.urlForVideo(filename: item.videoFilename)
            let imuSource = try VideoARStorage.urlForIMUCSV(filename: item.imuCSVFilename)
            let arSource = try VideoARStorage.urlForARCSV(filename: item.arCSVFilename)

            guard fileManager.fileExists(atPath: videoSource.path) else {
                throw VideoARItemExportError.missingFile(item.videoFilename)
            }
            guard fileManager.fileExists(atPath: imuSource.path) else {
                throw VideoARItemExportError.missingFile(item.imuCSVFilename)
            }
            guard fileManager.fileExists(atPath: arSource.path) else {
                throw VideoARItemExportError.missingFile(item.arCSVFilename)
            }

            let videoTarget = exportFolder.appendingPathComponent("\(identifier).mov")
            let imuTarget = exportFolder.appendingPathComponent("\(identifier)_imu.csv")
            let arTarget = exportFolder.appendingPathComponent("\(identifier)_ar.csv")

            try fileManager.copyItem(at: videoSource, to: videoTarget)
            try fileManager.copyItem(at: imuSource, to: imuTarget)
            try fileManager.copyItem(at: arSource, to: arTarget)
        }

        return exportFolder
    }

    private func createExportFolder() throws -> URL {
        let base = fileManager.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderURL = base.appendingPathComponent("VideoARExport-\(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
