//
//  VideoARItem.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation
import SwiftData

@Model
final class VideoARItem {
    var id: UUID
    var timestamp: Date
    var videoFilename: String
    var imuCSVFilename: String
    var arCSVFilename: String
    var duration: TimeInterval
    var imuSampleCount: Int
    var arSampleCount: Int

    init(id: UUID = UUID(),
         timestamp: Date,
         videoFilename: String,
         imuCSVFilename: String,
         arCSVFilename: String,
         duration: TimeInterval,
         imuSampleCount: Int,
         arSampleCount: Int) {
        self.id = id
        self.timestamp = timestamp
        self.videoFilename = videoFilename
        self.imuCSVFilename = imuCSVFilename
        self.arCSVFilename = arCSVFilename
        self.duration = duration
        self.imuSampleCount = imuSampleCount
        self.arSampleCount = arSampleCount
    }
}
