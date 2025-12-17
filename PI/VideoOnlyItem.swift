//
//  VideoOnlyItem.swift
//  PI
//
//  Created by Rongwei Ji on 12/16/25.
//

import Foundation
import SwiftData

@Model
final class VideoOnlyItem {
    var id: UUID
    var timestamp: Date
    var videoFilename: String
    var duration: TimeInterval
    var resolutionLabel: String

    init(id: UUID = UUID(),
         timestamp: Date,
         videoFilename: String,
         duration: TimeInterval,
         resolutionLabel: String) {
        self.id = id
        self.timestamp = timestamp
        self.videoFilename = videoFilename
        self.duration = duration
        self.resolutionLabel = resolutionLabel
    }
}
