//
//  ARPoseSample.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation

struct ARPoseSample: Codable {
    let timestamp: Date
    let positionX: Double
    let positionY: Double
    let positionZ: Double
    let orientationX: Double
    let orientationY: Double
    let orientationZ: Double
    let orientationW: Double
}
