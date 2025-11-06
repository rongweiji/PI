//
//  VideoItem.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation
import SwiftData

@Model
final class VideoItem {
    var id: UUID
    var timestamp: Date
    var videoFilename: String
    var imuCSVFilename: String
    var duration: TimeInterval
    var sampleCount: Int

    init(id: UUID = UUID(),
         timestamp: Date,
         videoFilename: String,
         imuCSVFilename: String,
         duration: TimeInterval,
         sampleCount: Int) {
        self.id = id
        self.timestamp = timestamp
        self.videoFilename = videoFilename
        self.imuCSVFilename = imuCSVFilename
        self.duration = duration
        self.sampleCount = sampleCount
    }
}
