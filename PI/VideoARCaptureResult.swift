//
//  VideoARCaptureResult.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation

struct VideoARCaptureResult {
    let videoURL: URL
    let imuSamples: [IMUSample]
    let arSamples: [ARPoseSample]
    let duration: TimeInterval
}
