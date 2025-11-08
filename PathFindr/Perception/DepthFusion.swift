// DepthFusion.swift
import Foundation
import ARKit

enum DepthFusion {
    static func medianDepthMeters(in bbox: CGRect, depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly); defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let rowStride = bpr / MemoryLayout<Float32>.size
        let fx = Int(max(0, floor(bbox.origin.x * CGFloat(w))))
        let fy = Int(max(0, floor(bbox.origin.y * CGFloat(h))))
        let fw = Int(min(CGFloat(w - fx), ceil(bbox.size.width * CGFloat(w))))
        let fh = Int(min(CGFloat(h - fy), ceil(bbox.size.height * CGFloat(h))))
        var samples: [Float] = []
        samples.reserveCapacity(fw*fh/4)
        for y in stride(from: fy, to: fy+fh, by: 2) {
            let row = base.assumingMemoryBound(to: Float32.self).advanced(by: y * rowStride)
            for x in stride(from: fx, to: fx+fw, by: 2) {
                let v = row[x]
                if v.isFinite && v > 0.05 && v < 20 { samples.append(v) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        let m = samples[samples.count/2]
        return m
    }

    static func metersToFeet(_ m: Float) -> Float { m * 3.28084 }
}
