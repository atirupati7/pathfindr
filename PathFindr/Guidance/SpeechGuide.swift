// SpeechGuide.swift
import Foundation
import AVFoundation

@MainActor
final class SpeechGuide: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    override init() { super.init(); synth.delegate = self }

    func speak(_ text: String) {
        let utter = AVSpeechUtterance(string: text)
        utter.rate = 0.45
        utter.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utter)
    }
}
