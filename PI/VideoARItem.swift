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
    var framesZipFilename: String = ""
    var timestampsFilename: String = ""
    var poseCSVFilename: String = ""
    var duration: TimeInterval
    var frameCount: Int = 0

    init(id: UUID = UUID(),
         timestamp: Date,
         framesZipFilename: String,
         timestampsFilename: String,
         poseCSVFilename: String,
         duration: TimeInterval,
         frameCount: Int) {
        self.id = id
        self.timestamp = timestamp
        self.framesZipFilename = framesZipFilename
        self.timestampsFilename = timestampsFilename
        self.poseCSVFilename = poseCSVFilename
        self.duration = duration
        self.frameCount = frameCount
    }
}
