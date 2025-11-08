//
//  ContentView.swift
//  PathFindr
//
//  Created by Elchin Hasanov on 11/8/25.
//

import SwiftUI
import ARKit

// Backwards compatibility wrapper for original ContentView reference
struct ContentView: View { @EnvironmentObject var navigator: Navigator; var body: some View { NavigationRootView() } }

struct NavigationRootView: View {
    @EnvironmentObject var navigator: Navigator
    @State private var showMap: Bool = false
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

            if showMap {
                MiniMapView(grid: navigator.gridSnapshot)
                    .frame(height: 200)
                    .transition(.opacity)
            }

            Toggle("Developer Map", isOn: $showMap)
                .toggleStyle(SwitchToggleStyle())
                .padding(.horizontal)

            Toggle("AI Descriptions", isOn: $navigator.useGeminiDescriptions)
                .toggleStyle(SwitchToggleStyle())
                .padding(.horizontal)

            // Hold-to-speak test button
            holdToSpeakButton
            if !lastTranscript.isEmpty {
                Text("Heard: \(lastTranscript)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .onAppear { navigator.announceStartup(); transcriber.requestPermissions() }
    }

    private func toggle() {
        if navigator.isRunning { navigator.stop() } else { navigator.start() }
    }
}

private extension NavigationRootView {
    var holdToSpeakButton: some View {
        let isRec = transcriber.isRecording
        return ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isRec ? Color.orange : Color.blue)
            Text(isRec ? "Listening…" : "Hold to Speak")
                .foregroundColor(.white)
                .bold()
                .padding()
        }
        .frame(height: 60)
        .accessibilityLabel("Hold to Speak")
        .accessibilityHint("Press and hold to record a voice command")
        .onLongPressGesture(minimumDuration: .infinity, perform: {}, onPressingChanged: { pressing in
            if pressing { transcriber.start() } else {
                transcriber.stop { text in
                    lastTranscript = text
                    print("[Voice] Final transcript: \(text)")
                }
            }
        })
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
