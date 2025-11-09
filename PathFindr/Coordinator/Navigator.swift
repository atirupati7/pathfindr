// Navigator.swift
import Foundation
import ARKit
import AVFoundation
import SwiftUI
import Combine
import FirebaseCore

final class Navigator: NSObject, ObservableObject {
    enum Mode { case scanning, cruise, avoid }
    enum GeminiMode { case streaming, prompted }
    
    struct State { var statusText: String = "Idle" }

    @Published var state = State()
    @Published private(set) var isRunning = false
    @Published var gridSnapshot: OccupancyGrid? = nil
    @Published var isARReady = false

    private let ar = ARDepthSession()
    private let floor = FloorEstimator()
    private let detector = ObjectDetector()
    private let speech = SpeechGuide()
    private let beacon = SpatialBeacon()
    private let haptics = Haptics()
    private let motion = MotionHeading()
    // Use Firebase for conversation history storage
    private let conversationService: ConversationService
    private let gemini: GeminiClient

    private var grid = OccupancyGrid.makeDefault()
    private var lastAnnounced: [String: Float] = [:] // label -> lastFeet
    private var lastCommandTime: CFTimeInterval = 0
    private var mode: Mode = .scanning
    @Published var useGeminiDescriptions: Bool = true
    private var lastGeminiText: String = ""
    private var geminiMode: GeminiMode = .streaming
    private var pendingFrame: ARFrame?
    private var isProcessingPrompt = false
    private var wasStreamingBeforePrompt = false

    private var depthTimer: CADisplayLink?

    override init() {
        // Initialize conversation service (Firebase if available, otherwise Mock)
        // Check if Firebase is initialized, if not use MockConversationService as fallback
        if FirebaseApp.app() != nil {
            self.conversationService = FirebaseConversationService(userId: "default_user")
            print("[Navigator] Using Firebase for conversation history")
        } else {
            self.conversationService = MockConversationService()
            print("[Navigator] Firebase not available, using MockConversationService")
        }
        // Initialize GeminiClient with conversation service
        self.gemini = GeminiClient(apiKey: APIKeys.geminiAPIKey, conversationService: conversationService)
        super.init()
        ar.delegate = self
        // Start AR session immediately for live video feed
        ar.start()
    }

    func announceStartup() { speech.speak("Path Finder ready") }
    
    // Stop any ongoing speech
    func stopSpeech() {
        speech.stop()
    }
    
    // Stop streaming descriptions (called when user starts recording)
    func stopStreaming() {
        // Stop any ongoing speech immediately
        speech.stop()
        
        // Track if streaming should be active after the prompt
        // Resume streaming if guidance is running and Gemini descriptions are enabled
        let shouldStream = (isRunning && useGeminiDescriptions)
        
        if shouldStream {
            // We want to resume streaming after the prompt, so mark it
            wasStreamingBeforePrompt = true
            // Switch to prompted mode to stop current streaming
            if geminiMode == .streaming {
                geminiMode = .prompted
            }
            isProcessingPrompt = true
            print("[Navigator] Stopped streaming for recording (will resume after prompt if guidance still running)")
        } else {
            // If streaming shouldn't be active, don't resume it later
            wasStreamingBeforePrompt = false
            print("[Navigator] Streaming not active - guidance not running or Gemini disabled")
        }
    }
    
    // Handle voice prompt from user
    func handleVoicePrompt(_ transcript: String, currentFrame: ARFrame?) {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        print("[Navigator] Voice prompt received: \(transcript)")
        
        // Ensure we're in prompted mode (stopStreaming may have already set this)
        // But preserve wasStreamingBeforePrompt if it was already set
        if !isProcessingPrompt {
            // Only set wasStreamingBeforePrompt if it wasn't already set by stopStreaming()
            // Check if streaming should be active based on current state
            let shouldStream = (isRunning && useGeminiDescriptions)
            if shouldStream && geminiMode == .streaming {
                wasStreamingBeforePrompt = true
            }
            geminiMode = .prompted
            isProcessingPrompt = true
        }
        
        // Stop any ongoing speech immediately
        speech.stop()
        
        if wasStreamingBeforePrompt {
            print("[Navigator] Will resume streaming after prompt is answered")
        }
        
        // Store current frame if available
        if let frame = currentFrame {
            pendingFrame = frame
        }
        
        // Determine if user expects long or short answer
        let expectsLongAnswer = determineAnswerLength(transcript: transcript)
        
        // Get the most recent frame
        guard let frame = currentFrame ?? pendingFrame else {
            print("[Navigator] No frame available for prompted query")
            speech.speak("Please wait for camera to initialize") {
                // After speaking error message, resume streaming if it was active
                self.isProcessingPrompt = false
                if self.wasStreamingBeforePrompt {
                    // Only resume streaming if guidance is still running and Gemini descriptions are enabled
                    if self.isRunning && self.useGeminiDescriptions {
                        self.geminiMode = .streaming
                        self.wasStreamingBeforePrompt = false
                        print("[Navigator] Resumed streaming mode after error")
                    } else {
                        self.wasStreamingBeforePrompt = false
                        print("[Navigator] Not resuming streaming - guidance stopped or Gemini disabled")
                    }
                }
            }
            return
        }
        
        // Send to Gemini with conversation history
        gemini.queryPrompted(frame: frame, userPrompt: transcript, expectsLongAnswer: expectsLongAnswer) { [weak self] response in
            guard let self = self else { return }
            
            if let answer = response, !answer.isEmpty {
                print("[Navigator] Prompted answer: \(answer)")
                Task { @MainActor in
                    // Speak the answer and only resume streaming after speech is fully finished
                    self.speech.speak(answer) {
                        // Speech finished - now safe to resume streaming
                        self.isProcessingPrompt = false
                        if self.wasStreamingBeforePrompt {
                            // Only resume streaming if guidance is still running and Gemini descriptions are enabled
                            if self.isRunning && self.useGeminiDescriptions {
                                self.geminiMode = .streaming
                                self.wasStreamingBeforePrompt = false
                                print("[Navigator] Resumed streaming mode after prompt answer finished")
                            } else {
                                // Guidance was stopped or Gemini descriptions disabled, don't resume
                                self.wasStreamingBeforePrompt = false
                                print("[Navigator] Not resuming streaming - guidance stopped or Gemini disabled")
                            }
                        }
                        self.pendingFrame = nil
                    }
                }
            } else {
                print("[Navigator] No response from prompted query")
                Task { @MainActor in
                    self.speech.speak("I couldn't process that request") {
                        // Speech finished - now safe to resume streaming
                        self.isProcessingPrompt = false
                        if self.wasStreamingBeforePrompt {
                            // Only resume streaming if guidance is still running and Gemini descriptions are enabled
                            if self.isRunning && self.useGeminiDescriptions {
                                self.geminiMode = .streaming
                                self.wasStreamingBeforePrompt = false
                                print("[Navigator] Resumed streaming mode after error message finished")
                            } else {
                                // Guidance was stopped or Gemini descriptions disabled, don't resume
                                self.wasStreamingBeforePrompt = false
                                print("[Navigator] Not resuming streaming - guidance stopped or Gemini disabled")
                            }
                        }
                        self.pendingFrame = nil
                    }
                }
            }
        }
    }
    
    // Determine if user expects a long or short answer based on question type
    private func determineAnswerLength(transcript: String) -> Bool {
        let lowercased = transcript.lowercased()
        
        // Keywords that suggest long answers
        let longAnswerKeywords = [
            "describe", "what is happening", "tell me about", "explain", "details",
            "what do you see", "what's around", "what's in", "what are"
        ]
        
        // Keywords that suggest short answers
        let shortAnswerKeywords = [
            "where is", "where's", "where are", "how many", "what color",
            "read", "what does it say", "what's written", "what sign", "what menu"
        ]
        
        // OCR tasks are usually short
        let ocrKeywords = [
            "read", "what does it say", "what's written", "what sign", "what menu",
            "crosswalk", "signal", "text", "words"
        ]
        
        // Check for OCR first (usually short)
        for keyword in ocrKeywords {
            if lowercased.contains(keyword) {
                return false
            }
        }
        
        // Check for short answer keywords
        for keyword in shortAnswerKeywords {
            if lowercased.contains(keyword) {
                return false
            }
        }
        
        // Check for long answer keywords
        for keyword in longAnswerKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }
        
        // Default to short for navigation/quick questions
        return false
    }

    func start() {
        isRunning = true
        state.statusText = "Starting…"
        motion.start()
        // AR session is already started in init, don't restart it
        depthTimer = CADisplayLink(target: self, selector: #selector(tickTimer))
        depthTimer?.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 20)
        depthTimer?.add(to: .main, forMode: .common)
        // Mute guidance start speech
        // speech.speak("Guidance started")
    }

    func stop() {
        isRunning = false
        // Keep AR session running for live video feed
        motion.stop()
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
        // Don't announce objects if user is sitting down
        guard motion.isUserMoving else { return }
        
        let rounded = max(0.5, (distanceFeet * 2).rounded() / 2) // nearest 0.5, min 0.5
        let last = lastAnnounced[label] ?? .greatestFiniteMagnitude
        // Change threshold 15% to allow more updates
        if !last.isFinite || abs(rounded - last)/max(rounded, 0.1) > 0.15 {
            lastAnnounced[label] = rounded
            let name = label.capitalized
            let feetStr = (rounded.truncatingRemainder(dividingBy: 1) == 0) ? String(Int(rounded)) : String(format: "%.1f", rounded)
            print("[Navigator] Speak det: \(name) \(feetStr) ft")
            // Note: Object detection announcements are now handled by Gemini descriptions with distance
            // speech.speak("\(name) \(feetStr) feet ahead")
        }
    }
    
    // Calculate distance text from depth data
    private func calculateDistanceText(from frame: ARFrame) -> String {
        guard let depthMap = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap else {
            return ""
        }
        
        // Get forward depth (center region of frame)
        let depth = approximateForwardDepth(depthMap: depthMap)
        guard depth > 0 && depth < 10 else { // Valid range: 0.05m to 10m
            return ""
        }
        
        // Convert to feet
        let feet = depth * 3.28084
        let rounded = max(0.5, (feet * 2).rounded() / 2) // nearest 0.5, min 0.5
        let feetStr = (rounded.truncatingRemainder(dividingBy: 1) == 0) ? String(Int(rounded)) : String(format: "%.1f", rounded)
        
        return "\(feetStr) feet"
    }
    
    // Approximate forward depth from depth map (center region)
    private func approximateForwardDepth(depthMap: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return -1 }
        
        var samples: [Float] = []
        // Sample center region of frame (forward view)
        for y in stride(from: h/3, to: h*2/3, by: 4) {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
            for x in stride(from: w/3, to: w*2/3, by: 4) {
                let v = row[x]
                if v.isFinite && v > 0.05 && v < 10 {
                    samples.append(v)
                }
            }
        }
        
        samples.sort()
        return samples.isEmpty ? -1 : samples[samples.count/2] // Return median depth
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
        // Update AR ready state
        if !isARReady && session.arIsReady {
            isARReady = true
        }
        
        guard isRunning else { return }
        
        // Store latest frame for prompted queries
        pendingFrame = frame
        
        floor.process(frame: frame)
        grid.reset()
        grid.integrateDepth(frame: frame, floorY: floor.floorY)
        grid.inflate(radiusCells: 1)
        checkDangerStop(frame: frame)
        processDetections(frame: frame)
        
        // Only do streaming descriptions if not in prompted mode and not processing a prompt
        if useGeminiDescriptions && geminiMode == .streaming && !isProcessingPrompt {
            gemini.maybeDescribe(frame: frame) { [weak self] text in
                guard let self, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
                
                // Double-check we're still in streaming mode (in case mode changed while request was in flight)
                guard self.geminiMode == .streaming && !self.isProcessingPrompt else {
                    print("[Navigator] Ignoring streaming response - mode changed to prompted")
                    return
                }
                
                // Log and dedupe
                print("[Navigator] Gemini streaming: \(t)")
                guard t != self.lastGeminiText else { return }
                self.lastGeminiText = t
                
                // Calculate distance to nearest object using depth data
                let distanceText = self.calculateDistanceText(from: frame)
                let finalText = distanceText.isEmpty ? t : "\(t), \(distanceText)"
                
                Task { @MainActor in self.speech.speak(finalText) }
            }
        } else if !useGeminiDescriptions {
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
    
    // Expose current frame for voice prompts
    var currentFrame: ARFrame? {
        return ar.arSession.currentFrame
    }
}
