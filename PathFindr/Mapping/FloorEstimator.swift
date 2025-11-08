// FloorEstimator.swift
import Foundation
import ARKit

final class FloorEstimator {
    private(set) var floorY: Float? = nil
    private var isEstimated = false

    func process(frame: ARFrame) {
        guard !isEstimated else { return }
    // Placeholder: use depth sampling once
    if let y = estimateFromDepth(frame: frame) { floorY = y; isEstimated = true }
    }

    private func estimateFromDepth(frame: ARFrame) -> Float? {
        guard let sceneDepth = frame.sceneDepth else { return nil }
        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly); defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        let h = CVPixelBufferGetHeight(depthMap)
        let w = CVPixelBufferGetWidth(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        var minY: Float = .greatestFiniteMagnitude
        let intr = frame.camera.intrinsics
        let fx = intr.columns.0.x
        let fy = intr.columns.1.y
        let cx = intr.columns.2.x
        let cy = intr.columns.2.y
        let camT = frame.camera.transform
        for v in stride(from: h/3, to: h, by: 4) { // bottom portion of image
            let row = base.advanced(by: v * bpr).assumingMemoryBound(to: Float32.self)
            for u in stride(from: 0, to: w, by: 4) {
                let d = row[u]
                if !d.isFinite || d < 0.2 || d > 6.0 { continue }
                let Xc = (Float(u) - cx)*d/fx
                let Yc = (Float(v) - cy)*d/fy
                let Zc = d
                let world = camT * simd_float4(Xc,Yc,Zc,1)
                if world.y < minY { minY = world.y }
            }
        }
        return minY.isFinite ? minY : nil
    }
}
