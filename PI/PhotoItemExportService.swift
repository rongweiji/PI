//
//  PhotoItemExportService.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation

enum PhotoItemExportError: LocalizedError {
    case noItems

    var errorDescription: String? {
        switch self {
        case .noItems:
            return "There are no photos to export yet."
        }
    }
}

struct PhotoItemExportService {
    private let fileManager = FileManager.default

    func export(items: [PhotoItem]) throws -> URL {
        guard !items.isEmpty else { throw PhotoItemExportError.noItems }

        let exportFolder = try createExportFolder()

        let csvURL = exportFolder.appendingPathComponent("imu-data.csv")
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var csvLines: [String] = [
            "id,timestamp,image_filename,accelerometerX,accelerometerY,accelerometerZ,gyroscopeX,gyroscopeY,gyroscopeZ"
        ]

        for (index, item) in items.enumerated() {
            let identifier = String(format: "%04d", index + 1)
            let imageFilename: String

            if let imageData = item.imageData {
                imageFilename = "\(identifier).jpg"
                let imageURL = exportFolder.appendingPathComponent(imageFilename)
                try imageData.write(to: imageURL, options: .atomic)
            } else {
                imageFilename = ""
            }

            let timestamp = isoFormatter.string(from: item.timestamp)
            let accelX = formatted(item.accelerometerX)
            let accelY = formatted(item.accelerometerY)
            let accelZ = formatted(item.accelerometerZ)
            let gyroX = formatted(item.gyroscopeX)
            let gyroY = formatted(item.gyroscopeY)
            let gyroZ = formatted(item.gyroscopeZ)

            let row = [
                identifier,
                timestamp,
                imageFilename,
                accelX,
                accelY,
                accelZ,
                gyroX,
                gyroY,
                gyroZ
            ].joined(separator: ",")
            csvLines.append(row)
        }

        let csvContent = csvLines.joined(separator: "\n")
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        return exportFolder
    }

    private func createExportFolder() throws -> URL {
        let base = fileManager.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folderName = "PhotoExport-\(formatter.string(from: Date()))"
        let folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
