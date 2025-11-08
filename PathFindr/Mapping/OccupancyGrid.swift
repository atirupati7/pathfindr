// OccupancyGrid.swift
import Foundation
import ARKit

struct OccupancyGrid {
    // Grid stored row-major: index = z*width + x
    let width: Int
    let depth: Int
    let resolution: Float // meters per cell
    var originToRightMeters: Float { Float(width) * 0.5 * resolution }
    var forwardMeters: Float { Float(depth) * resolution }
    var cells: [UInt8] // 0 free, >0 occupied (or inflated)

    mutating func reset() {
        // Avoid overlapping access; simplest is to reassign a new zeroed buffer.
        if !cells.isEmpty { cells = Array(repeating: 0, count: cells.count) }
    }

    func isOccupied(x: Int, z: Int) -> Bool {
        guard x >= 0 && x < width && z >= 0 && z < depth else { return true }
        return cells[z*width + x] != 0
    }

    mutating func occupy(x: Int, z: Int) {
        guard x >= 0 && x < width && z >= 0 && z < depth else { return }
        cells[z*width + x] = 1
    }

    mutating func inflate(radiusCells: Int) {
        guard radiusCells > 0 else { return }
        var out = cells
        let r = radiusCells
        for z in 0..<depth {
            for x in 0..<width {
                if cells[z*width + x] == 0 { continue }
                for dz in -r...r {
                    for dx in -r...r {
                        if dx*dx + dz*dz <= r*r { // disk
                            let nx = x + dx, nz = z + dz
                            if nx >= 0 && nx < width && nz >= 0 && nz < depth {
                                out[nz*width + nx] = max(out[nz*width + nx], 1)
                            }
                        }
                    }
                }
            }
        }
        cells = out
    }
}

extension OccupancyGrid {
    static func makeDefault() -> OccupancyGrid {
        // width 4m, depth 6m, res 0.1m -> 40x60
        let res: Float = 0.1
        let width = Int(round(4.0 / Double(res)))
        let depth = Int(round(6.0 / Double(res)))
        return OccupancyGrid(width: width, depth: depth, resolution: res, cells: Array(repeating: 0, count: width*depth))
    }
}

// MARK: Depth Integration
extension OccupancyGrid {
    mutating func integrateDepth(frame: ARFrame, floorY: Float?) {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let widthPx = CVPixelBufferGetWidth(depthMap)
        let heightPx = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }

        // Camera parameters
        let intr = frame.camera.intrinsics
        let fx = intr.columns.0.x
        let fy = intr.columns.1.y
        let cx = intr.columns.2.x
        let cy = intr.columns.2.y
        let camTransform = frame.camera.transform

        // Prepare stride
        for v in stride(from: 0, to: heightPx, by: 2) { // decimate for perf
            let row = base.advanced(by: v * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for u in stride(from: 0, to: widthPx, by: 2) {
                let d = row[u]
                if !d.isFinite || d <= 0.05 || d > 8.0 { continue }
                // Back-project to camera space
                let Xc = (Float(u) - cx) * d / fx
                let Yc = (Float(v) - cy) * d / fy
                let Zc = d
                let pCam = simd_float4(Xc, Yc, Zc, 1)
                let pWorld = camTransform * pCam

                // Filter by height above floor
                if let floorY = floorY {
                    let h = pWorld.y - floorY
                    if h < 0.15 || h > 1.7 { continue }
                }

                // Transform into local user-centric grid axes relative to camera pose
                let pLocal = pCam // camera forward is +Z in ARKit
                let x = pLocal.x
                let z = pLocal.z
                if z < 0.0 { continue } // behind
                let gx = Int(floor((x + originToRightMeters) / resolution))
                let gz = Int(floor(z / resolution))
                occupy(x: gx, z: gz)
            }
        }
    }
}
