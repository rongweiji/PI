//
//  IMUSessionExportService.swift
//  PI
//
//  Created by Rongwei Ji on 11/24/25.
//

import Foundation

enum IMUSessionExportError: LocalizedError {
    case noItems
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "There are no IMU sessions to export yet."
        case .missingFile(let filename):
            return "Missing IMU file for export: \(filename)"
        }
    }
}

struct IMUSessionExportService {
    private let fileManager = FileManager.default

    func export(items: [IMUSessionItem]) throws -> URL {
        guard !items.isEmpty else { throw IMUSessionExportError.noItems }

        let exportFolder = try createExportFolder()

        for (index, item) in items.enumerated() {
            let identifier = String(format: "%04d", index + 1)
            let sourceURL = try IMUSessionStorage.urlForIMUCSV(filename: item.imuCSVFilename)

            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw IMUSessionExportError.missingFile(item.imuCSVFilename)
            }

            let targetURL = exportFolder.appendingPathComponent("\(identifier).csv")
            try fileManager.copyItem(at: sourceURL, to: targetURL)
        }

        return exportFolder
    }

    private func createExportFolder() throws -> URL {
        let base = fileManager.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderName = "IMUExport-\(formatter.string(from: Date()))"
        let folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}
