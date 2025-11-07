//
//  IMUSessionItem.swift
//  PI
//
//  Created by Rongwei Ji on 11/24/25.
//

import Foundation
import SwiftData

@Model
final class IMUSessionItem {
    var id: UUID
    var timestamp: Date
    var duration: TimeInterval
    var sampleCount: Int
    var imuCSVFilename: String
    var samplingRateHz: Double = 30

    init(id: UUID = UUID(),
         timestamp: Date,
         duration: TimeInterval,
         sampleCount: Int,
         imuCSVFilename: String,
         samplingRateHz: Double = 30) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.sampleCount = sampleCount
        self.imuCSVFilename = imuCSVFilename
        self.samplingRateHz = samplingRateHz
    }
}
