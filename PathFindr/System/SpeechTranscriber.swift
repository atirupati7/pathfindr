// SpeechTranscriber.swift
// Simple press-and-hold speech-to-text using Apple's Speech framework.
import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class SpeechTranscriber: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var finalHandler: ((String) -> Void)?

    @Published private(set) var isRecording = false
    private var lastText = ""

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized { print("[Voice] Speech auth not granted: \(status)") }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            if !ok { print("[Voice] Microphone permission not granted") }
        }
    }

    func start() {
        guard !isRecording else { return }
        lastText = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let text = result?.bestTranscription.formattedString { self.lastText = text }
                if let r = result, r.isFinal {
                    self.finish(with: self.lastText)
                } else if error != nil {
                    self.finish(with: self.lastText)
                }
            }

            isRecording = true
            print("[Voice] Recording started")
        } catch {
            print("[Voice] Start error: \(error)")
            stop { _ in }
        }
    }

    func stop(onFinal: @escaping (String) -> Void) {
        finalHandler = onFinal
        guard isRecording else { onFinal(lastText); return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        print("[Voice] Recording stopped, waiting final…")
        
        // Reconfigure audio session back to playback mode for speech output
        // This ensures volume is restored after recording
        reconfigureAudioSessionForPlayback()

        // Fallback in case we don't get a final callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.finish(with: self?.lastText ?? "")
        }
    }
    
    private func reconfigureAudioSessionForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use .playback category with .spokenAudio mode for maximum speech volume
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            print("[Voice] Audio session reconfigured for playback")
        } catch {
            print("[Voice] Failed to reconfigure audio session for playback: \(error)")
        }
    }

    private func finish(with text: String) {
        task?.cancel(); task = nil
        request = nil
        finalHandler?(text)
        finalHandler = nil
    }
}
