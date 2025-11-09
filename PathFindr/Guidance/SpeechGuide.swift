// SpeechGuide.swift
import Foundation
import AVFoundation

@MainActor
final class SpeechGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?
    
    override init() {
        super.init()
        synth.delegate = self
        // Initial audio session configuration
        reconfigureAudioSession()
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        completionHandler = completion
        
        // Reconfigure audio session each time we speak to ensure proper playback mode
        // This is important after recording stops, as the session might still be in .playAndRecord mode
        reconfigureAudioSession()
        
        let utter = AVSpeechUtterance(string: text)
        utter.rate = 0.45
        utter.volume = 1.0 // Maximum volume (relative to system volume)
        utter.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utter)
    }
    
    private func reconfigureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use .playback category with .spokenAudio mode for maximum speech volume
            // This overrides any previous session configuration (e.g., from recording)
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[SpeechGuide] Failed to configure audio session: \(error)")
        }
    }
    
    func stop() {
        synth.stopSpeaking(at: .immediate)
        completionHandler = nil
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let handler = completionHandler
        completionHandler = nil
        handler?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completionHandler = nil
    }
}
