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

    // Expose session for UI preview and anchor access
    var arSession: ARSession { session }

    func start() {
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
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        isRunning = false
    }

    // MARK: ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        delegate?.arDepthSession(self, didUpdate: frame)
    }
}
