import XCTest
@testable import PathFindr

final class AStarTests: XCTestCase {
    func testPathAvoidsObstacle() {
        var grid = OccupancyGrid(width: 10, depth: 10, resolution: 0.1, cells: Array(repeating: 0, count: 100))
        for z in 0..<5 { grid.occupy(x: 5, z: z) }
        let start = SIMD2<Int>(5,0)
        let goal = SIMD2<Int>(5,9)
        let path = AStar.path(from: start, to: goal, in: grid)
        XCTAssertNotNil(path)
        for p in path! { if p.y < 5 { XCTAssertNotEqual(p.x, 5) } }
    }
}

final class DepthFusionTests: XCTestCase {
    func testMedianIgnoresInvalid() {
        let w = 8, h = 8
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        var pb: CVPixelBuffer? = nil
        CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_DepthFloat32, attrs, &pb)
        guard let depth = pb else { XCTFail(); return }
        CVPixelBufferLockBaseAddress(depth, [])
        let base = CVPixelBufferGetBaseAddress(depth)!.assumingMemoryBound(to: Float32.self)
        for i in 0..<(w*h) { base[i] = (i % 2 == 0) ? 1.0 : Float.nan }
        CVPixelBufferUnlockBaseAddress(depth, [])
        let bbox = CGRect(x: 0, y: 0, width: 1, height: 1)
        let med = DepthFusion.medianDepthMeters(in: bbox, depthMap: depth)
        XCTAssertEqual(med, 1.0)
    }
}

final class CommandSynthesizerTests: XCTestCase {
    func testTurnNormalization() {
        let grid = OccupancyGrid(width: 20, depth: 20, resolution: 0.1, cells: Array(repeating: 0, count: 400))
        let path: [SIMD2<Int>] = [SIMD2(10,0), SIMD2(12,2), SIMD2(14,4)]
        let cmd = CommandSynthesizer.synthesize(path: path, grid: grid, currentYawRadians: 0)
        XCTAssertNotNil(cmd)
        XCTAssertTrue(cmd!.turnDegrees > 0)
    }
}
