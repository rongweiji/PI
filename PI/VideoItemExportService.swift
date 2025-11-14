//
//  VideoItemExportService.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation

enum VideoItemExportError: LocalizedError {
    case noItems
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "There are no videos to export yet."
        case .missingFile(let name):
            return "Missing file for export: \(name)"
        }
    }
}

struct VideoItemExportService {
    private let fileManager = FileManager.default

    func export(items: [VideoItem]) throws -> URL {
        guard !items.isEmpty else { throw VideoItemExportError.noItems }

        let exportFolder = try createExportFolder()

        for (index, item) in items.enumerated() {
            let identifier = String(format: "%04d", index + 1)
            let videoSource = try VideoStorage.urlForVideo(filename: item.videoFilename)
            let imuSource = try VideoStorage.urlForIMUCSV(filename: item.imuCSVFilename)

            guard fileManager.fileExists(atPath: videoSource.path) else {
                throw VideoItemExportError.missingFile(item.videoFilename)
            }
            guard fileManager.fileExists(atPath: imuSource.path) else {
                throw VideoItemExportError.missingFile(item.imuCSVFilename)
            }

            let videoTarget = exportFolder.appendingPathComponent("\(identifier).mov")
            let imuTarget = exportFolder.appendingPathComponent("\(identifier)_imu.csv")

            try fileManager.copyItem(at: videoSource, to: videoTarget)
            try fileManager.copyItem(at: imuSource, to: imuTarget)

        }

        return exportFolder
    }

    private func createExportFolder() throws -> URL {
        let base = fileManager.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderName = "VideoExport-\(formatter.string(from: Date()))"
        let folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
