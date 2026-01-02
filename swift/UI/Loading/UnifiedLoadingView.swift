//
//  UnifiedLoadingView.swift
//  nethack
//
//  Full-screen immersive dungeon loading experience.
//  No cards, no boxes - pure dungeon atmosphere.
//
//  Features:
//  - Massive glowing @ symbol (hero emerging from darkness)
//  - Animated torch flames on sides
//  - Rising ember particles
//  - Stone dungeon background
//  - Atmospheric fog layer
//

import Combine
import SwiftUI

// MARK: - Loading State

enum LoadingState: Equatable {
    case launching
    case downloading(String)
    case exiting(String)

    var message: String {
        switch self {
        case .launching:
            return "Descending into the dungeon..."
        case .downloading(let name):
            return "Summoning \(name) from the clouds..."
        case .exiting(let message):
            return message
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .launching:
            return "Loading game"
        case .downloading(let name):
            return "Downloading character \(name) from iCloud"
        case .exiting:
            return "Saving and exiting game"
        }
    }
}

// MARK: - Ember Particle

private struct Ember: Identifiable {
    let id = UUID()
    var x: CGFloat      // 0-1 normalized
    var y: CGFloat      // 0-1 normalized
    var size: CGFloat
    var opacity: CGFloat
    var speed: CGFloat
    var wobblePhase: CGFloat
    var wobbleAmp: CGFloat

    static func random() -> Ember {
        Ember(
            x: CGFloat.random(in: 0.15...0.85),
            y: CGFloat.random(in: 0.5...1.1),
            size: CGFloat.random(in: 3...8),
            opacity: CGFloat.random(in: 0.4...0.9),
            speed: CGFloat.random(in: 0.02...0.06),
            wobblePhase: CGFloat.random(in: 0...(.pi * 2)),
            wobbleAmp: CGFloat.random(in: 0.01...0.03)
        )
    }
}

// MARK: - Torch Flame

private struct TorchFlame: View {
    let side: HorizontalEdge
    @State private var flameOffset: CGFloat = 0
    @State private var flameScale: CGFloat = 1.0
    @State private var glowIntensity: CGFloat = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum HorizontalEdge {
        case left, right
    }

    var body: some View {
        ZStack {
            // Torch glow (large, soft)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.3 * glowIntensity),
                            Color.orange.opacity(0.1 * glowIntensity),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .offset(y: -20)

            // Flame core
            VStack(spacing: 0) {
                // Flame
                ZStack {
                    // Outer flame
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.8),
                                    Color.orange,
                                    Color.yellow.opacity(0.9)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 24, height: 50)
                        .scaleEffect(x: flameScale, y: flameScale * 1.1)
                        .offset(x: flameOffset)
                        .blur(radius: 3)

                    // Inner flame (brighter)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.orange,
                                    Color.yellow,
                                    Color.white.opacity(0.9)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 12, height: 35)
                        .scaleEffect(x: flameScale * 0.9, y: flameScale)
                        .offset(x: flameOffset * 0.5, y: 5)
                        .blur(radius: 1)
                }

                // Torch handle
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.25, blue: 0.1),
                                Color(red: 0.3, green: 0.18, blue: 0.08)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 10, height: 60)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            startFlameAnimation()
        }
    }

    private func startFlameAnimation() {
        // Flame flicker
        withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
            flameOffset = CGFloat.random(in: -3...3)
        }

        withAnimation(.easeInOut(duration: 0.2).repeatForever(autoreverses: true)) {
            flameScale = CGFloat.random(in: 0.85...1.15)
        }

        // Glow pulse
        withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
            glowIntensity = CGFloat.random(in: 0.6...1.0)
        }
    }
}

// MARK: - Unified Loading View

struct UnifiedLoadingView: View {
    let state: LoadingState

    // Animation states
    @State private var heroGlow: CGFloat = 0.6
    @State private var heroScale: CGFloat = 1.0
    @State private var embers: [Ember] = []
    @State private var fogOffset: CGFloat = 0
    @State private var textOpacity: CGFloat = 0
    @State private var dotIndex = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    // Timers
    private let dotTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    // MARK: - Sizing

    private var heroSize: CGFloat { isPhone ? 140 : 200 }
    private var glowSize: CGFloat { isPhone ? 300 : 400 }
    private var messageSize: CGFloat { isPhone ? 18 : 22 }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Deep dungeon background
                dungeonBackground

                // Layer 2: Stone texture overlay
                stoneTexture
                    .opacity(0.15)

                // Layer 3: Fog layer
                if !reduceMotion {
                    fogLayer
                }

                // Layer 4: Torches on sides
                HStack {
                    TorchFlame(side: .left)
                        .offset(x: isPhone ? 30 : 60, y: geo.size.height * 0.15)

                    Spacer()

                    TorchFlame(side: .right)
                        .offset(x: isPhone ? -30 : -60, y: geo.size.height * 0.15)
                }

                // Layer 5: Ember particles
                if !reduceMotion {
                    emberParticles(in: geo.size)
                }

                // Layer 6: Hero @ symbol (center)
                heroSymbol
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.38)

                // Layer 7: Message text
                VStack(spacing: 16) {
                    Spacer()

                    Text(state.message)
                        .font(.system(size: messageSize, weight: .medium, design: .serif))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 4)
                        .shadow(color: .orange.opacity(0.3), radius: 10)
                        .opacity(textOpacity)

                    loadingDots
                        .opacity(textOpacity)

                    Spacer()
                        .frame(height: geo.size.height * 0.12)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            initializeEmbers()
            startAnimations()
            triggerHaptic()
        }
        .onReceive(dotTimer) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                dotIndex = (dotIndex + 1) % 3
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }

    // MARK: - Dungeon Background

    private var dungeonBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.02, blue: 0.05),
                Color(red: 0.08, green: 0.04, blue: 0.02),
                Color(red: 0.05, green: 0.02, blue: 0.01),
                Color.black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Stone Texture

    private var stoneTexture: some View {
        Canvas { context, size in
            // Create stone-like pattern
            for _ in 0..<200 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let rectSize = CGFloat.random(in: 2...6)
                let opacity = CGFloat.random(in: 0.1...0.3)

                context.fill(
                    Rectangle().path(in: CGRect(x: x, y: y, width: rectSize, height: rectSize)),
                    with: .color(Color.gray.opacity(opacity))
                )
            }
        }
    }

    // MARK: - Fog Layer

    private var fogLayer: some View {
        ZStack {
            // Lower fog
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.3),
                    Color(red: 0.2, green: 0.1, blue: 0.05).opacity(0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .offset(y: fogOffset)

            // Vignette
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.9)
                ],
                center: .center,
                startRadius: 100,
                endRadius: 500
            )
        }
    }

    // MARK: - Hero Symbol

    private var heroSymbol: some View {
        ZStack {
            // Massive outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.orange.opacity(0.4 * heroGlow),
                            Color.orange.opacity(0.2 * heroGlow),
                            Color.red.opacity(0.1 * heroGlow),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: heroSize * 0.3,
                        endRadius: glowSize / 2
                    )
                )
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 30)

            // Inner bright glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.yellow.opacity(0.5 * heroGlow),
                            Color.orange.opacity(0.3 * heroGlow),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: heroSize * 0.8
                    )
                )
                .frame(width: heroSize * 1.6, height: heroSize * 1.6)
                .blur(radius: 15)

            // The @ - Hero emerging from darkness
            Text("@")
                .font(.system(size: heroSize, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.95, blue: 0.7),
                            Color(red: 1.0, green: 0.8, blue: 0.4),
                            Color(red: 0.9, green: 0.6, blue: 0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black, radius: 2, x: 2, y: 3)
                .shadow(color: .orange.opacity(0.8), radius: 20)
                .shadow(color: .yellow.opacity(0.4), radius: 40)
                .scaleEffect(heroScale)
        }
    }

    // MARK: - Ember Particles

    private func emberParticles(in size: CGSize) -> some View {
        TimelineView(.animation(minimumInterval: 1/30)) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate

                for ember in embers {
                    drawEmber(ember, in: context, size: canvasSize, time: time)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawEmber(_ ember: Ember, in context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let elapsed = CGFloat(time)

        // Rising motion with wobble
        let progress = (elapsed * ember.speed).truncatingRemainder(dividingBy: 1.2)
        let y = (ember.y - progress) * size.height
        let wobble = sin(elapsed * 3 + ember.wobblePhase) * ember.wobbleAmp * size.width
        let x = ember.x * size.width + wobble

        // Fade out as it rises
        let fadeProgress = max(0, min(1, progress / 0.8))
        let alpha = ember.opacity * (1 - fadeProgress)

        guard alpha > 0.05, y > 0 else { return }

        // Glow
        let glowRect = CGRect(
            x: x - ember.size * 3,
            y: y - ember.size * 3,
            width: ember.size * 6,
            height: ember.size * 6
        )
        context.fill(
            Circle().path(in: glowRect),
            with: .radialGradient(
                Gradient(colors: [
                    Color.orange.opacity(alpha * 0.5),
                    Color.clear
                ]),
                center: CGPoint(x: x, y: y),
                startRadius: 0,
                endRadius: ember.size * 3
            )
        )

        // Core
        let coreRect = CGRect(
            x: x - ember.size / 2,
            y: y - ember.size / 2,
            width: ember.size,
            height: ember.size
        )
        context.fill(
            Circle().path(in: coreRect),
            with: .color(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(alpha))
        )
    }

    // MARK: - Loading Dots

    private var loadingDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotIndex == index ? Color.orange : Color.white.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotIndex == index ? 1.4 : 1.0)
                    .shadow(
                        color: dotIndex == index ? .orange.opacity(0.6) : .clear,
                        radius: 6
                    )
            }
        }
    }

    // MARK: - Animations

    private func initializeEmbers() {
        embers = (0..<25).map { _ in Ember.random() }
    }

    private func startAnimations() {
        guard !reduceMotion else {
            textOpacity = 1
            return
        }

        // Hero glow pulse
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            heroGlow = 1.0
        }

        // Hero breathe
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            heroScale = 1.05
        }

        // Fog drift
        withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
            fogOffset = 30
        }

        // Text fade in
        withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
            textOpacity = 1
        }
    }

    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}

// MARK: - Previews

#Preview("Launch") {
    UnifiedLoadingView(state: .launching)
        .preferredColorScheme(.dark)
}

#Preview("Download") {
    UnifiedLoadingView(state: .downloading("Gandalf"))
        .preferredColorScheme(.dark)
}

#Preview("Exit") {
    UnifiedLoadingView(state: .exiting("Saving your progress..."))
        .preferredColorScheme(.dark)
}
