// CommandSynthesizer.swift
import Foundation

struct Command { let turnDegrees: Float; let forwardMeters: Float }

enum CommandSynthesizer {
    static func synthesize(path: [SIMD2<Int>], grid: OccupancyGrid, currentYawRadians: Float) -> Command? {
        guard path.count >= 2 else { return Command(turnDegrees: 0, forwardMeters: 0) }
        let origin = SIMD2<Float>(Float(grid.width/2), 0)
        let next = path[min(3, path.count-1)] // look a bit ahead
        let dx = Float(next.x) - origin.x
        let dz = Float(next.y) - origin.y
        let angle = atan2f(dx, dz) // desired heading in grid frame (z forward)
        let yaw = currentYawRadians // already in camera frame assumption
        var delta = (angle - yaw) * 180 / .pi
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        let distCells = hypotf(dx, dz)
        let meters = min(distCells * grid.resolution, 1.0)
        return Command(turnDegrees: delta, forwardMeters: meters)
    }
}
