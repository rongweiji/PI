//
//  PhotoItem.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation
import SwiftData

@Model
final class PhotoItem {
    var timestamp: Date
    var imageData: Data?
    var photoMetadata: Data?
    var accelerometerX: Double
    var accelerometerY: Double
    var accelerometerZ: Double
    var gyroscopeX: Double
    var gyroscopeY: Double
    var gyroscopeZ: Double

    init(timestamp: Date, imageData: Data? = nil, photoMetadata: Data? = nil,
         accelerometerX: Double = 0.0, accelerometerY: Double = 0.0, accelerometerZ: Double = 0.0,
         gyroscopeX: Double = 0.0, gyroscopeY: Double = 0.0, gyroscopeZ: Double = 0.0) {
        self.timestamp = timestamp
        self.imageData = imageData
        self.photoMetadata = photoMetadata
        self.accelerometerX = accelerometerX
        self.accelerometerY = accelerometerY
        self.accelerometerZ = accelerometerZ
        self.gyroscopeX = gyroscopeX
        self.gyroscopeY = gyroscopeY
        self.gyroscopeZ = gyroscopeZ
    }
}
