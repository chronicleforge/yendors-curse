//
//  nethackApp.swift
//  nethack
//
//  Created by nwagensonner on 15.09.25.
//

import SwiftUI

@main
struct nethackApp: App {
    @Environment(\.scenePhase) var scenePhase
    @State private var gameManager = NetHackGameManager()
    @State private var deathFlowController = DeathFlowController()

    init() {
        // Configure logging - disable noisy categories by default
        #if DEBUG
        Log.setLevel(.debug)
        Log.printStatus()
        // SLOG/LogShipper removed - was causing crashes
        #else
        Log.setLevel(.info)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(gameManager)
                .environment(deathFlowController)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // App is entering background - save happens automatically on exitToMenu()
            print("[App] Entering background - game will be saved on next exit")
            // NOTE: Background save removed - users must explicitly exit to save
            // This gives them control over save timing
        case .inactive:
            // App is becoming inactive (e.g., control center, app switcher)
            print("[App] App becoming inactive")
        case .active:
            // App is becoming active
            print("[App] App becoming active")
        @unknown default:
            break
        }
    }
}
