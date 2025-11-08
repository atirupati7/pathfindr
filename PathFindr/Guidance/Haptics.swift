// Haptics.swift
import Foundation
import CoreHaptics

@MainActor
final class Haptics {
    private var engine: CHHapticEngine?
    init() { engine = try? CHHapticEngine(); try? engine?.start() }

    /// Generic danger buzz (short continuous)
    func danger(intensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let events = [
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0.1, min(1.0, intensity))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0, duration: 0.3)
        ]
        let pattern = try? CHHapticPattern(events: events, parameters: [])
        let player = try? engine?.makePlayer(with: pattern!)
        try? player?.start(atTime: 0)
    }

    /// Proximity pulses: frequency and intensity increase as distance decreases.
    /// - Parameters:
    ///   - meters: current distance to nearest obstacle
    ///   - kind: semantic kind hints shaping the feel
    func proximity(meters: Float, kind: String) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        let d = max(0.1, min(3.0, meters))
        // Map distance to intensity [0.2,1.0] and rate [1.5Hz .. 6Hz]
        let intensity = Float(1.0) - (d / 3.0) * 0.8 // closer => stronger
        let baseRate: Double = 1.5 + Double((1.0 - min(1.0, d/3.0))) * 4.5
        // Shape by kind
        let sharp: Float
        switch kind.lowercased() {
        case "wall": sharp = 0.8
        case "table": sharp = 0.6
        case "chair": sharp = 0.5
        case "person": sharp = 0.7
        default: sharp = 0.6
        }
        // Build a 1-second pattern with evenly spaced pulses at computed rate
        let duration: Double = 1.0
        let count = max(1, Int(round(baseRate * duration)))
        var events: [CHHapticEvent] = []
        let gap = duration / Double(count)
        for i in 0..<count {
            let t = Double(i) * gap
            let e = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0.2, min(1.0, intensity))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)
            ], relativeTime: t)
            events.append(e)
        }
        let pattern = try? CHHapticPattern(events: events, parameters: [])
        let player = try? engine?.makePlayer(with: pattern!)
        try? player?.start(atTime: 0)
    }

    func stopBuzz() { engine?.stop(completionHandler: nil); engine = try? CHHapticEngine(); try? engine?.start() }
}
