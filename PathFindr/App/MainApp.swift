// MainApp.swift
// PathFindr
// Entry point launching NavigationView
import SwiftUI
import FirebaseCore

@main
struct MainApp: App {
    // Initialize Firebase before creating Navigator
    init() {
        // Initialize Firebase first
        FirebaseApp.configure()
        print("[MainApp] Firebase initialized")
    }
    
    // Create Navigator after Firebase is initialized
    @StateObject private var navigator = Navigator()
    
    var body: some Scene {
        WindowGroup {
            NavigationRootView()
                .environmentObject(navigator)
        }
    }
}
