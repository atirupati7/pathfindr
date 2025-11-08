// SpatialBeacon.swift
import Foundation
import AVFoundation

@MainActor
final class SpatialBeacon {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var monoFormat: AVAudioFormat!
    private var isRunning = false

    init() {
        engine.attach(environment)
        engine.attach(player)

        // Match hardware sample rate; use mono for player->environment
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        monoFormat = AVAudioFormat(standardFormatWithSampleRate: hwFormat.sampleRate, channels: 1)!

        engine.connect(player, to: environment, format: monoFormat)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        environment.renderingAlgorithm = .HRTF
        buildPingBuffer(sampleRate: hwFormat.sampleRate)
    }

    private func buildPingBuffer(sampleRate: Double) {
        let frames = Int(sampleRate * 0.25)
        let format = monoFormat!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        let ptr = buf.floatChannelData![0]
        for i in 0..<frames {
            let t = Double(i)/sampleRate
            let env = exp(-4.0 * t)
            let val = sin(2*Double.pi*880*t) * env * 0.3
            ptr[i] = Float(val)
        }
        buffer = buf
    }

    func start(at position: AVAudio3DPoint) {
        if !engine.isRunning { try? engine.start() }
        environment.listenerPosition = .init(x: 0, y: 0, z: 0)
        player.position = position
        if let buffer, player.isPlaying == false {
            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        }
        if !isRunning { player.play(); isRunning = true }
    }

    func update(position: AVAudio3DPoint) { player.position = position }
    func stop() { player.stop(); isRunning = false }
}
