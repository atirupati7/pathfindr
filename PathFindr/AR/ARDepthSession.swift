// ARDepthSession.swift
// Wraps ARSession configuration & delegate forwarding
import Foundation
import ARKit

protocol ARDepthSessionDelegate: AnyObject {
    func arDepthSession(_ session: ARDepthSession, didUpdate frame: ARFrame)
}

final class ARDepthSession: NSObject, ARSessionDelegate {
    private let session = ARSession()
    weak var delegate: ARDepthSessionDelegate?
    private(set) var isRunning = false
    private(set) var isReady = false // Track when AR is ready for smooth video
    private var isFirstStart = true

    // Expose session for UI preview and anchor access
    var arSession: ARSession { session }
    
    // Expose ready state
    var arIsReady: Bool { isReady }

    func start() {
        guard !isRunning else { return } // Don't restart if already running
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .smoothedSceneDepth]) {
            config.frameSemantics.insert(.sceneDepth)
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        session.delegate = self
        
        // Only reset tracking on first start, not on subsequent starts
        let options: ARSession.RunOptions = isFirstStart ? [.resetTracking, .removeExistingAnchors] : []
        session.run(config, options: options)
        isFirstStart = false
        isRunning = true
        isReady = false // Will be set to true when tracking is normal
    }

    func stop() {
        // Don't actually stop - keep session running for live video feed
        // session.pause()
        // isRunning = false
    }

    // MARK: ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Mark as ready when tracking state is normal
        if !isReady && frame.camera.trackingState == .normal {
            isReady = true
            print("[AR] Session ready, tracking normal")
        }
        delegate?.arDepthSession(self, didUpdate: frame)
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[AR] Session failed: \(error.localizedDescription)")
        isReady = false
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("[AR] Session interrupted")
        isReady = false
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("[AR] Session interruption ended")
        // Session will become ready again when tracking resumes
    }
}
