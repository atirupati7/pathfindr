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

// Backwards compatibility wrapper for original ContentView reference
struct ContentView: View { @EnvironmentObject var navigator: Navigator; var body: some View { NavigationRootView() } }

struct NavigationRootView: View {
    @EnvironmentObject var navigator: Navigator
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var lastTranscript: String = ""
    @State private var isRecording = false
    @State private var isPressingButton = false

    var body: some View {
        ZStack {
            // Full screen camera preview - only show when AR is ready
            if navigator.isARReady {
                CameraPreview(session: navigator.session)
                    .edgesIgnoringSafeArea(.all)
            } else {
                // Show loading/initializing state
                Color.black
                    .edgesIgnoringSafeArea(.all)
                    .overlay {
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Initializing camera...")
                                .foregroundColor(.white)
                                .padding(.top, 8)
                        }
                    }
            }
            
            // Overlay UI at bottom
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    VStack(spacing: 12) {
                        Text(navigator.state.statusText)
                            .font(.headline)
                            .padding()
                            .background(.black.opacity(0.6))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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

                        // Hold to Speak button
                        HoldToSpeakButton(
                            isRecording: $isRecording,
                            isPressing: $isPressingButton,
                            onStartRecording: {
                                // Stop any ongoing speech immediately when starting to record
                                navigator.stopSpeech()
                                // Stop streaming descriptions and distance announcements
                                navigator.stopStreaming()
                                transcriber.start()
                            },
                            onStopRecording: {
                                transcriber.stop { text in
                                    DispatchQueue.main.async {
                                        // Send transcript to navigator for Gemini processing
                                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            lastTranscript = text
                                            navigator.handleVoicePrompt(text, currentFrame: navigator.currentFrame)
                                        }
                                    }
                                }
                            }
                        )

                        if !lastTranscript.isEmpty {
                            Text("Heard: \(lastTranscript)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .lineLimit(2)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear { navigator.announceStartup(); transcriber.requestPermissions() }
    }

    private func toggle() {
        if navigator.isRunning { navigator.stop() } else { navigator.start() }
    }
}

// MARK: Hold to Speak Button
struct HoldToSpeakButton: View {
    @Binding var isRecording: Bool
    @Binding var isPressing: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    
    var body: some View {
        ZStack {
            // Button background
            Circle()
                .fill(isRecording ? Color.red : (isPressing ? Color.orange : Color.blue))
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .scaleEffect(isPressing ? 0.9 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressing)
            
            // Button icon/text
            if isRecording {
                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "mic")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing {
                        isPressing = true
                        isRecording = true
                        // Haptic feedback when starting to record
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onStartRecording()
                        print("[HoldButton] Recording started")
                    }
                }
                .onEnded { _ in
                    if isPressing {
                        isPressing = false
                        isRecording = false
                        // Haptic feedback when stopping recording
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        onStopRecording()
                        print("[HoldButton] Recording stopped")
                    }
                }
        )
        .accessibilityLabel(isRecording ? "Recording, release to stop" : "Hold to speak")
        .accessibilityHint("Press and hold to record your voice")
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
