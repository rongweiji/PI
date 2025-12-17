//
//  VideoOnlyItemExportService.swift
//  PI
//
//  Created by Rongwei Ji on 12/16/25.
//

import Foundation
enum VideoOnlyItemExportServiceError: Error, LocalizedError {
    case failedToCreateFolder
    case missingVideo(VideoOnlyItem)

    var errorDescription: String? {
        switch self {
        case .failedToCreateFolder:
            return "Failed to create export folder."
        case .missingVideo(let item):
            return "Missing video file: \(item.videoFilename)"
        }
    }
}

final class VideoOnlyItemExportService {
    func export(items: [VideoOnlyItem]) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("videoonly_export_\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            throw VideoOnlyItemExportServiceError.failedToCreateFolder
        }

        for item in items {
            guard FileManager.default.fileExists(atPath: (try VideoOnlyStorage.urlForVideo(filename: item.videoFilename)).path) else {
                throw VideoOnlyItemExportServiceError.missingVideo(item)
            }
            let videoURL = try VideoOnlyStorage.urlForVideo(filename: item.videoFilename)
            let targetVideoURL = tempDir.appendingPathComponent(item.videoFilename)
            try FileManager.default.copyItem(at: videoURL, to: targetVideoURL)
        }

        return tempDir
    }
}
