// ObjectDetector.swift
import Foundation
import Vision
import CoreMedia
import QuartzCore

struct DetectedObject { let label: String; let bbox: CGRect; let confidence: Float }

final class ObjectDetector {
    private let queue = DispatchQueue(label: "detector.queue")
    private var lastRequestTime: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 0.12 // ~8 Hz

    func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([DetectedObject]) -> Void) {
        let now = CACurrentMediaTime()
        guard now - lastRequestTime >= minInterval else { return }
        lastRequestTime = now
        let request = VNDetectRectanglesRequest { req, _ in
            let rects = (req.results as? [VNRectangleObservation]) ?? []
            let objs: [DetectedObject] = rects.map { ob in
                DetectedObject(label: "object", bbox: ob.boundingBox, confidence: 0.5)
            }
            completion(objs)
        }
        request.minimumAspectRatio = 0.2
        request.maximumObservations = 10
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        queue.async {
            do { try handler.perform([request]) } catch { completion([]) }
        }
    }
}
