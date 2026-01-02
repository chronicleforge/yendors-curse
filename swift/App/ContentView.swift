//
//  ContentView.swift
//  nethack
//
//  Created by nwagensonner on 15.09.25.
//

import SwiftUI

struct ContentView: View {
    @Environment(NetHackGameManager.self) var gameManager
    @Environment(DeathFlowController.self) var deathFlow
    @State private var isLoading = true
    @State private var showLaunchScreen = true
    @State private var testMode = 0  // 1=red, 2=scenekit, 3=gradient, 4=no-scale, 5=scale-only, 6=actual, 0=normal

    var testModeNames = [
        "Normal App",
        "1: Red Fill",
        "2: SceneKit",
        "3: Gradient",
        "4: No Scale",
        "5: Scale Only",
        "6: Actual Game"
    ]

    var body: some View {
        Group {  // SWIFTUI-L-002: Group for mutually exclusive states, NOT ZStack
            // TEST MODE - Comment this out to return to normal
            if testMode == 1 {
                // STEP 1: Just a red screen - should fill entire iPhone
                TestGameView()
            } else if testMode == 2 {
                // STEP 2: SceneKit only
                TestSceneKitView()
            } else if testMode == 3 {
                // STEP 3: Gradient test
                TestMinimalGameView()
            } else if testMode == 4 {
                // STEP 4: NetHack without scaling
                TestNetHackWithoutScaling(gameManager: gameManager)
            } else if testMode == 5 {
                // STEP 5: Just the scaling wrapper
                TestScalingOnly()
            } else if testMode == 6 {
                // STEP 6: Actual game view (no scaling)
                TestActualGameView(gameManager: gameManager)
            }
            // NORMAL MODE - Simple phase-based logic
            else if showLaunchScreen {
                // Launch screen while dylib loads
                LaunchScreenView()
                    .transition(.opacity)
                    .onAppear {
                        Task { await initializeGame() }
                    }
            } else if deathFlow.phase == .showing {
                // Death Screen - full view (not overlay)
                DeathScreenView()
                    .transition(.opacity)
                    .onAppear {
                        print("[ContentView] Showing DeathScreenView")
                    }
            } else if !gameManager.isGameRunning && deathFlow.phase == .alive {
                // Character Selection - only when NOT in death flow
                SimplifiedCharacterSelectionView(gameManager: gameManager)
                    .transition(.opacity)
                    .onAppear {
                        print("[ContentView] Showing CharacterSelection, isGameRunning=\(gameManager.isGameRunning), deathPhase=\(deathFlow.phase)")
                    }
            } else {
                // Game View - also shown during death animation (.animating phase)
                NetHackGameView(gameManager: gameManager)
                    .transition(.slide)
                    .ignoresSafeArea()
                    .onAppear {
                        print("[ContentView] Showing GameView, isGameRunning=\(gameManager.isGameRunning), deathPhase=\(deathFlow.phase)")
                    }
            }
        }
        .overlay(alignment: .bottomTrailing) {  // SWIFTUI-L-002: overlay() for test UI, not ZStack child
            if testMode > 0 {
                testModeOverlay
            }
        }
        .preferredColorScheme(.dark)
    }

    // SWIFTUI-L-002: Extract overlay for clarity
    private var testModeOverlay: some View {
        VStack(spacing: 10) {
            Text("Test: \(testModeNames[min(testMode, testModeNames.count - 1)])")
                .font(.caption)
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)

            HStack(spacing: 15) {
                // Previous button
                Button(action: {
                    testMode = max(0, testMode - 1)
                }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.blue))
                }

                // Next button
                Button(action: {
                    testMode = min(6, testMode + 1)
                }) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.blue))
                }
            }
        }
        .padding()
        .ignoresSafeArea()
    }

    private func initializeGame() async {
        // Initialize dylib and game systems
        // This gives time for the launch screen to show

        // Ensure minimum display time for smooth transition
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds minimum

        // Hide launch screen with animation
        withAnimation(.easeOut(duration: 0.5)) {
            showLaunchScreen = false
        }
    }
}