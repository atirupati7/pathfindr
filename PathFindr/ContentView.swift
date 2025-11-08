//
//  ContentView.swift
//  PathFindr
//
//  Created by Elchin Hasanov on 11/8/25.
//

import SwiftUI
import ARKit
import UIKit
import AVFoundation
import MediaPlayer

// Backwards compatibility wrapper for original ContentView reference
struct ContentView: View { @EnvironmentObject var navigator: Navigator; var body: some View { NavigationRootView() } }

struct NavigationRootView: View {
    @EnvironmentObject var navigator: Navigator
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var lastTranscript: String = ""

    var body: some View {
        VStack(spacing: 16) {
            CameraPreview(session: navigator.session)
                .frame(height: 240)
                .overlay(alignment: .topLeading) {
                    Text(navigator.overlayText)
                        .font(.caption.monospaced())
                        .padding(6)
                        .background(.black.opacity(0.4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            Text(navigator.state.statusText)
                .font(.headline)
                .accessibilityLabel(navigator.state.statusText)

            Button(action: toggle) {
                Text(navigator.isRunning ? "Stop Guidance" : "Start Guidance")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(navigator.isRunning ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityLabel(navigator.isRunning ? "Stop" : "Start")
            .accessibilityHint("Double tap to " + (navigator.isRunning ? "stop navigation" : "start navigation"))

            Toggle("AI Descriptions", isOn: $navigator.useGeminiDescriptions)
                .toggleStyle(SwitchToggleStyle())
                .padding(.horizontal)

            if !lastTranscript.isEmpty {
                Text("Heard: \(lastTranscript)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(SideButtonHandler(transcriber: transcriber, onTranscript: { text in
            lastTranscript = text
            // Send transcript to navigator for Gemini processing
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                navigator.handleVoicePrompt(text, currentFrame: navigator.currentFrame)
            }
        }))
        .onAppear { navigator.announceStartup(); transcriber.requestPermissions() }
    }

    private func toggle() {
        if navigator.isRunning { navigator.stop() } else { navigator.start() }
    }
}

// MARK: Side Button Handler (Action Button primary, Volume Button fallback)
struct SideButtonHandler: UIViewControllerRepresentable {
    let transcriber: SpeechTranscriber
    let onTranscript: (String) -> Void
    
    func makeUIViewController(context: Context) -> SideButtonViewController {
        let controller = SideButtonViewController()
        controller.transcriber = transcriber
        controller.onTranscript = onTranscript
        return controller
    }
    
    func updateUIViewController(_ uiViewController: SideButtonViewController, context: Context) {
        uiViewController.transcriber = transcriber
        uiViewController.onTranscript = onTranscript
    }
}

class SideButtonViewController: UIViewController {
    var transcriber: SpeechTranscriber?
    var onTranscript: ((String) -> Void)?
    
    // Action Button support
    private var isPressing = false
    
    // Volume Button fallback support
    private var volumeView: MPVolumeView!
    private var isRecording = false
    private var lastVolume: Float = 0
    private var volumeTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        
        // Setup volume button monitoring (fallback)
        setupVolumeMonitoring()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        lastVolume = AVAudioSession.sharedInstance().outputVolume
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    // MARK: Action Button Support (Primary)
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            // Detect Action Button (menu press type) - primary method
            if press.type == .menu {
                isPressing = true
                startRecording()
                handled = true
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
    
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if press.type == .menu {
                if isPressing {
                    isPressing = false
                    stopRecording()
                }
                handled = true
                break
            }
        }
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }
    
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if press.type == .menu {
                if isPressing {
                    isPressing = false
                    stopRecording()
                }
                handled = true
                break
            }
        }
        if !handled {
            super.pressesCancelled(presses, with: event)
        }
    }
    
    // MARK: Volume Button Support (Fallback)
    private func setupVolumeMonitoring() {
        // Create hidden volume view to intercept volume button presses
        volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.isHidden = true
        view.addSubview(volumeView)
        
        // Monitor volume changes
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkVolumeChange()
        }
    }
    
    private func checkVolumeChange() {
        let currentVolume = AVAudioSession.sharedInstance().outputVolume
        
        // Detect volume button press (volume changed)
        if abs(currentVolume - lastVolume) > 0.01 {
            let volumeIncreased = currentVolume > lastVolume
            handleVolumeButtonPress(isVolumeUp: volumeIncreased)
            // Reset volume to original to prevent actual volume change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.resetVolume()
            }
        }
        
        lastVolume = currentVolume
    }
    
    private func handleVolumeButtonPress(isVolumeUp: Bool) {
        // Only use volume button if Action Button is not being used
        guard !isPressing else { return }
        
        if isVolumeUp {
            // Volume Up = Start recording
            if !isRecording {
                startRecording()
                print("[Volume] Volume Up - Recording started")
            }
        } else {
            // Volume Down = Stop recording
            if isRecording {
                stopRecording()
                print("[Volume] Volume Down - Recording stopped")
            }
        }
    }
    
    private func resetVolume() {
        // Try to restore volume to prevent actual volume change
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        slider?.value = lastVolume
    }
    
    // MARK: Recording Control
    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        transcriber?.start()
        print("[Button] Recording started")
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        
        transcriber?.stop { [weak self] text in
            DispatchQueue.main.async {
                self?.onTranscript?(text)
                print("[Voice] Final transcript: \(text)")
            }
        }
        print("[Button] Recording stopped")
    }
    
    deinit {
        volumeTimer?.invalidate()
    }
}

struct MiniMapView: View {
    let grid: OccupancyGrid?
    var body: some View {
        GeometryReader { geo in
            if let g = grid {
                let cellSize = min(geo.size.width / CGFloat(g.width), geo.size.height / CGFloat(g.depth))
                Canvas { ctx, size in
                    for z in 0..<g.depth {
                        for x in 0..<g.width {
                            if g.cells[z * g.width + x] != 0 {
                                let rect = CGRect(x: CGFloat(x) * cellSize, y: CGFloat(z) * cellSize, width: cellSize, height: cellSize)
                                ctx.fill(Path(rect), with: .color(.orange))
                            }
                        }
                    }
                    // user origin marker
                    let originX = CGFloat(g.width/2) * cellSize
                    let originRect = CGRect(x: originX - cellSize*0.5, y: -cellSize*0.5, width: cellSize, height: cellSize)
                    ctx.fill(Path(originRect), with: .color(.blue))
                }
                .background(Color.black.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No grid")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview { NavigationRootView().environmentObject(Navigator()) }

// MARK: AR Camera Preview
struct CameraPreview: UIViewRepresentable {
    let session: ARSession?
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.automaticallyUpdatesLighting = true
        v.contentScaleFactor = UIScreen.main.scale
        if let s = session { v.session = s }
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if let s = session, uiView.session != s { uiView.session = s }
    }
}
