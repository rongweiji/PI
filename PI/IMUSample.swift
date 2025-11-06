//
//  IMUSample.swift
//  PI
//
//  Created by Rongwei Ji on 11/5/25.
//

import Foundation

struct IMUSample: Codable {
    let timestamp: Date
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    let rotationX: Double
    let rotationY: Double
    let rotationZ: Double
}
