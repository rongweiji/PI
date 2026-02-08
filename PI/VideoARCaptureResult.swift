//
//  VideoARCaptureResult.swift
//  PI
//
//  Created by Rongwei Ji on 11/29/25.
//

import Foundation

struct VideoARCaptureResult {
    let framesZipURL: URL
    let timestampsURL: URL
    let poseCSVURL: URL
    let duration: TimeInterval
    let frameCount: Int
}
