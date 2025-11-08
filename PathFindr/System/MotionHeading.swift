// MotionHeading.swift
import Foundation
import CoreMotion

final class MotionHeading {
    private let motion = CMMotionManager()
    private(set) var currentYawRadians: Float = 0

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let m = motion else { return }
            // Use attitude yaw (already fused); ARKit might be more accurate but fallback
            self?.currentYawRadians = Float(m.attitude.yaw)
        }
    }

    func stop() { motion.stopDeviceMotionUpdates() }
}
