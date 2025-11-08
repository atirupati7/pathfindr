// Navigator.swift
import Foundation
import ARKit
import AVFoundation
import SwiftUI
import Combine

final class Navigator: NSObject, ObservableObject {
    enum Mode { case scanning, cruise, avoid }
    struct State { var statusText: String = "Idle" }

    @Published var state = State()
    @Published private(set) var isRunning = false
    @Published var gridSnapshot: OccupancyGrid? = nil

    private let ar = ARDepthSession()
    private let floor = FloorEstimator()
    private let detector = ObjectDetector()
    private let speech = SpeechGuide()
    private let beacon = SpatialBeacon()
    private let haptics = Haptics()
    private let motion = MotionHeading()
    private let gemini = GeminiClient(apiKey: "AIzaSyAxhQo9ovt2fhs6flIQ_mkA7Y7D0mcMY0s")

    private var grid = OccupancyGrid.makeDefault()
    private var lastAnnounced: [String: Float] = [:] // label -> lastFeet
    private var lastCommandTime: CFTimeInterval = 0
    private var mode: Mode = .scanning
    @Published var useGeminiDescriptions: Bool = true
    private var lastGeminiText: String = ""

    private var depthTimer: CADisplayLink?

    override init() {
        super.init()
        ar.delegate = self
    }

    func announceStartup() { speech.speak("Path Finder ready") }

    func start() {
        isRunning = true
        state.statusText = "Starting…"
        motion.start()
        ar.start()
        depthTimer = CADisplayLink(target: self, selector: #selector(tickTimer))
        depthTimer?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 20)
        depthTimer?.add(to: .main, forMode: .common)
        // Mute guidance start speech
        // speech.speak("Guidance started")
    }

    func stop() {
        isRunning = false
        ar.stop(); motion.stop()
        depthTimer?.invalidate(); depthTimer = nil
        beacon.stop(); haptics.stopBuzz()
        state.statusText = "Stopped"
        // Mute guidance stop speech
        // speech.speak("Guidance stopped")
    }

    @objc private func tickTimer() {
        // AR frames are delivered via delegate; here we throttle planning & UI
        gridSnapshot = grid
    }

    private func processDetections(frame: ARFrame) {
        // Use plane anchors as a light semantic hint (tables are often horizontal planes around 0.7-1.0m high).
        var semanticDetections: [DetectedObject] = []
        for a in frame.anchors {
            if let p = a as? ARPlaneAnchor {
                if p.alignment == .horizontal {
                    // Heuristic: mid-height horizontal plane could be table.
                    let tableLabel = "table"
                    semanticDetections.append(DetectedObject(label: tableLabel, bbox: CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), confidence: 0.5))
                } else if p.alignment == .vertical {
                    // Vertical plane: likely wall/partition; ignore.
                }
            }
        }

        detector.detect(pixelBuffer: frame.capturedImage) { [weak self] detections in
            guard let self = self else { return }
            guard let depth = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap else { return }
            for d in (semanticDetections + detections) {
                if let m = DepthFusion.medianDepthMeters(in: d.bbox, depthMap: depth) {
                    let ft = DepthFusion.metersToFeet(m)
                    self.maybeSpeak(label: d.label, distanceFeet: ft)
                }
            }
        }
    }

    private func maybeSpeak(label: String, distanceFeet: Float) {
        let rounded = max(0.5, (distanceFeet * 2).rounded() / 2) // nearest 0.5, min 0.5
        let last = lastAnnounced[label] ?? .greatestFiniteMagnitude
        // Change threshold 15% to allow more updates
        if !last.isFinite || abs(rounded - last)/max(rounded, 0.1) > 0.15 {
            lastAnnounced[label] = rounded
            let name = label.capitalized
            let feetStr = (rounded.truncatingRemainder(dividingBy: 1) == 0) ? String(Int(rounded)) : String(format: "%.1f", rounded)
            print("[Navigator] Speak det: \(name) \(feetStr) ft")
            // speech.speak("\(name) \(feetStr) feet ahead")
        }
    }

    private func planAndGuide() {
        let now = CACurrentMediaTime()
        guard now - lastCommandTime > 0.6 else { return }
        lastCommandTime = now
        // start and goal in grid cells
        let start = SIMD2<Int>(grid.width/2, 0)
        let goalZ = min(grid.depth-1, Int(round(3.0 / Double(grid.resolution))))
        let goal = SIMD2<Int>(grid.width/2, goalZ)
        guard let path = AStar.path(from: start, to: goal, in: grid) else {
            state.statusText = "No path"
            // speech.speak("Stop. Obstacle ahead.")
            haptics.danger(intensity: 1)
            return
        }
        if let cmd = CommandSynthesizer.synthesize(path: path, grid: grid, currentYawRadians: motion.currentYawRadians) {
            updateGuidance(cmd: cmd)
        }
    }

    private func updateGuidance(cmd: Command) {
        // Qualitative direction: left / straight / right
        let turn = cmd.turnDegrees
        let dir: String
        if turn < -15 { dir = "left" }
        else if turn > 15 { dir = "right" }
        else { dir = "straight" }

        let feetF = DepthFusion.metersToFeet(cmd.forwardMeters)
        let feet = max(1, Int(round(feetF)))
        state.statusText = "Turn \(dir), walk \(feet) ft"
        // speech.speak("Turn \(dir). Walk \(feet) feet")
        // spatial beacon at next waypoint ~1m ahead in camera frame (x right, z forward)
        let px = Float(cmd.forwardMeters * sin(cmd.turnDegrees * .pi / 180))
        let pz = Float(cmd.forwardMeters * cos(cmd.turnDegrees * .pi / 180))
        beacon.start(at: AVAudio3DPoint(x: px, y: 0, z: pz))
    }

    private func checkDangerStop(frame: ARFrame) {
    // Corridor scan: band ±0.5 m around center; LiDAR-only semantics (no Gemini influence).
        let centerX = grid.width / 2
        let halfWidthCells = max(0, Int(round(0.5 / grid.resolution)))
        let minX = max(0, centerX - halfWidthCells)
        let maxX = min(grid.width - 1, centerX + halfWidthCells)

        // Immediate danger zone (<= 1.5 m)
        let maxAheadDanger = Int(1.5 / grid.resolution)
        var nearestDangerZ: Int? = nil
        dangerLoop: for z in 0..<min(grid.depth, maxAheadDanger) {
            for x in minX...maxX {
                if grid.isOccupied(x: x, z: z) { nearestDangerZ = z; break dangerLoop }
            }
        }
        if nearestDangerZ != nil {
            // speech.speak("Stop. Obstacle ahead.")
            haptics.danger(intensity: 1)
        }

        // Proximity pulses (<= 3.0 m)
        let maxAheadProx = Int(3.0 / grid.resolution)
        var nearestProxZ: Int? = nil
        proxLoop: for z in 0..<min(grid.depth, maxAheadProx) {
            for x in minX...maxX {
                if grid.isOccupied(x: x, z: z) { nearestProxZ = z; break proxLoop }
            }
        }
        if let nz = nearestProxZ {
            let meters = Float(nz) * grid.resolution
            let kind = inferKindFromPlanes(frame: frame, maxDistance: meters + 0.3)
            print("[Navigator] Nearest corridor occupancy: \(String(format: "%.2f", meters)) m (kind=\(kind))")
            haptics.proximity(meters: meters, kind: kind)
            if meters <= 1.0 { haptics.danger(intensity: 0.9) }
        }
    }
}

extension Navigator: ARDepthSessionDelegate {
    func arDepthSession(_ session: ARDepthSession, didUpdate frame: ARFrame) {
        guard isRunning else { return }
        floor.process(frame: frame)
        grid.reset()
        grid.integrateDepth(frame: frame, floorY: floor.floorY)
        grid.inflate(radiusCells: 1)
    checkDangerStop(frame: frame)
        processDetections(frame: frame)
        if useGeminiDescriptions {
            gemini.maybeDescribe(frame: frame) { [weak self] text in
                guard let self, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
                // Log and dedupe
                print("[Navigator] Gemini: \(t)")
                guard t != self.lastGeminiText else { return }
                self.lastGeminiText = t
                Task { @MainActor in self.speech.speak(t) }
            }
        } else {
            planAndGuide()
        }
    }
}

// MARK: Plane-based semantic inference (LiDAR)
private extension Navigator {
    func inferKindFromPlanes(frame: ARFrame, maxDistance: Float) -> String {
        var bestKind = "object"
        var bestDist = maxDistance + 0.01
        let camInv = frame.camera.transform.inverse
        for case let plane as ARPlaneAnchor in frame.anchors {
            let worldPos = SIMD4<Float>(plane.transform.columns.3.x,
                                        plane.transform.columns.3.y,
                                        plane.transform.columns.3.z,
                                        1)
            let camPos4 = simd_mul(camInv, worldPos)
            let camPos = SIMD3<Float>(camPos4.x, camPos4.y, camPos4.z)
            if camPos.z <= 0 { continue }
            if camPos.z > maxDistance + 0.5 { continue }
            switch plane.alignment {
            case .vertical:
                if camPos.z < bestDist { bestDist = camPos.z; bestKind = "wall" }
            case .horizontal:
                let worldY = plane.transform.columns.3.y
                let baseFloor = floor.floorY ?? worldY - 0.8 // fallback approximate floor
                let height = worldY - baseFloor
                if height > 0.55 && height < 1.1 { // table-ish
                    if camPos.z < bestDist { bestDist = camPos.z; bestKind = "table" }
                }
            @unknown default: break
            }
        }
        return bestKind
    }
}

// MARK: UI accessors
extension Navigator {
    var session: ARSession? { ar.arSession }
    @MainActor var overlayText: String { String(format: "yaw: %.0f°", motion.currentYawRadians * 180 / .pi) }
}
