// MainApp.swift
// PathFindr
// Entry point launching NavigationView
import SwiftUI

@main
struct MainApp: App {
    @StateObject private var navigator = Navigator()
    var body: some Scene {
        WindowGroup {
            NavigationRootView()
                .environmentObject(navigator)
        }
    }
}
