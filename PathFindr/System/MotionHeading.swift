// MotionHeading.swift
import Foundation
import CoreMotion

final class MotionHeading {
    private let motion = CMMotionManager()
    private(set) var currentYawRadians: Float = 0
    private(set) var isUserMoving: Bool = true
    
    private var lastAcceleration: SIMD3<Double> = SIMD3(0, 0, 0)
    private var movementSamples: [Double] = []
    private let movementThreshold: Double = 0.1 // m/s^2 threshold for movement
    private let sampleWindowSize = 20 // Number of samples to consider

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let m = motion else { return }
            // Use attitude yaw (already fused); ARKit might be more accurate but fallback
            self?.currentYawRadians = Float(m.attitude.yaw)
            
            // Track movement using acceleration
            let accel = m.userAcceleration
            let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            
            self?.movementSamples.append(magnitude)
            if self?.movementSamples.count ?? 0 > self?.sampleWindowSize ?? 20 {
                self?.movementSamples.removeFirst()
            }
            
            // Calculate average movement over recent samples
            if let samples = self?.movementSamples, samples.count >= 10 {
                let avgMovement = samples.reduce(0, +) / Double(samples.count)
                self?.isUserMoving = avgMovement > (self?.movementThreshold ?? 0.1)
            }
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}
