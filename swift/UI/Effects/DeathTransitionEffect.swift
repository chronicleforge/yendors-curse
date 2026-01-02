//
//  DeathTransitionEffect.swift
//  nethack
//
//  Soul particle death transition effect for player death
//  Ethereal rising particles with dark overlay fade
//
//  Accessibility: Respects Reduce Motion - falls back to simple fade
//  Performance: Uses Canvas for efficient particle rendering
//

import SwiftUI
import Combine

// MARK: - Soul Particle Model

/// Individual soul particle with position, appearance, and animation properties
struct SoulParticle: Identifiable {
    let id = UUID()
    var x: CGFloat           // Horizontal position (0-1 normalized)
    var y: CGFloat           // Vertical position (0-1 normalized, 0 = bottom)
    var size: CGFloat        // Particle diameter in points
    var opacity: CGFloat     // Current opacity (0-1)
    var speed: CGFloat       // Vertical rise speed (points per frame)
    var drift: CGFloat       // Horizontal drift amplitude
    var phase: CGFloat       // Sine wave phase offset for horizontal drift
    var hue: CGFloat         // Color hue offset for gold/white variation
    
    /// Create a randomized soul particle
    static func random(in bounds: CGRect) -> SoulParticle {
        SoulParticle(
            x: CGFloat.random(in: 0.1...0.9),
            y: CGFloat.random(in: -0.1...0.3), // Start below or near bottom
            size: CGFloat.random(in: 8...24),
            opacity: CGFloat.random(in: 0.6...1.0),
            speed: CGFloat.random(in: 0.002...0.006), // Normalized speed
            drift: CGFloat.random(in: 0.01...0.04),   // Horizontal drift amplitude
            phase: CGFloat.random(in: 0...(.pi * 2)), // Random phase offset
            hue: CGFloat.random(in: 0...0.12)         // Slight gold-white variation
        )
    }
}

// MARK: - Death Transition Overlay

/// Full-screen death transition overlay with soul particles rising effect
/// 
/// Usage:
/// ```swift
/// ZStack {
///     GameView()
///     if showDeathTransition {
///         DeathTransitionOverlay(progress: $deathProgress)
///     }
/// }
/// ```
struct DeathTransitionOverlay: View {
    @Binding var progress: CGFloat  // 0 to 1 animation progress
    var particleCount: Int = 16     // Number of soul particles (12-20 recommended)
    var onComplete: (() -> Void)?   // Called when transition reaches 1.0
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [SoulParticle] = []
    @State private var animationTime: CGFloat = 0
    @State private var hasTriggeredComplete = false
    
    // Animation timing constants
    private let overlayFadeDuration: CGFloat = 2.0
    private let particleLifetime: CGFloat = 3.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dark overlay
                overlayBackground
                
                // Soul particles (skip if reduce motion)
                if !reduceMotion {
                    particleCanvas(in: geometry.size)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            initializeParticles()
            startAnimation()
        }
        .onChange(of: progress) { _, newValue in
            guard newValue >= 1.0, !hasTriggeredComplete else { return }
            hasTriggeredComplete = true
            onComplete?()
        }
    }
    
    // MARK: - Overlay Background
    
    private var overlayBackground: some View {
        // Multi-layer dark gradient for depth
        ZStack {
            // Base black
            Color.black
                .opacity(progress * 0.85)
            
            // Purple/red death tint
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.0, blue: 0.2).opacity(progress * 0.4),
                    Color(red: 0.1, green: 0.0, blue: 0.15).opacity(progress * 0.3),
                    Color.black.opacity(0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            
            // Vignette effect
            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(progress * 0.3)
                ],
                center: .center,
                startRadius: 100,
                endRadius: 500
            )
        }
    }
    
    // MARK: - Particle Canvas
    
    private func particleCanvas(in size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                for particle in particles {
                    drawParticle(
                        particle,
                        in: context,
                        size: canvasSize,
                        time: time,
                        progress: progress
                    )
                }
            }
        }
    }
    
    private func drawParticle(
        _ particle: SoulParticle,
        in context: GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        progress: CGFloat
    ) {
        // Calculate animated position
        let timeOffset = CGFloat(time) * particle.speed * 60 // ~60fps normalized
        let normalizedY = particle.y + timeOffset
        
        // Particle fades as it rises (visible between y: 0-1)
        let fadeProgress = min(1, max(0, normalizedY))
        let fadeOpacity = 1.0 - fadeProgress
        
        // Skip if particle has risen off screen or not yet visible
        guard normalizedY > -0.1, normalizedY < 1.2 else { return }
        guard fadeOpacity > 0.05 else { return }
        
        // Horizontal drift using sine wave
        let driftOffset = sin(timeOffset * 4 + particle.phase) * particle.drift
        let finalX = particle.x + driftOffset
        
        // Convert normalized coordinates to screen coordinates
        let screenX = finalX * size.width
        let screenY = (1 - normalizedY) * size.height // Invert Y (0 = bottom)
        
        // Calculate particle opacity based on progress and fade
        let particleOpacity = particle.opacity * fadeOpacity * min(1, progress * 2)
        
        // Create gradient for glow effect
        let baseColor = Color(
            hue: 0.1 + particle.hue, // Gold-white range
            saturation: 0.3 - (particle.hue * 0.5), // Less saturated for white
            brightness: 1.0
        )
        
        let glowColor = baseColor.opacity(particleOpacity * 0.3)
        let coreColor = Color.white.opacity(particleOpacity)
        
        // Draw outer glow
        let glowRect = CGRect(
            x: screenX - particle.size * 1.5,
            y: screenY - particle.size * 1.5,
            width: particle.size * 3,
            height: particle.size * 3
        )
        
        context.fill(
            Circle().path(in: glowRect),
            with: .radialGradient(
                Gradient(colors: [glowColor, .clear]),
                center: CGPoint(x: screenX, y: screenY),
                startRadius: 0,
                endRadius: particle.size * 1.5
            )
        )
        
        // Draw core
        let coreRect = CGRect(
            x: screenX - particle.size * 0.3,
            y: screenY - particle.size * 0.3,
            width: particle.size * 0.6,
            height: particle.size * 0.6
        )
        
        context.fill(
            Circle().path(in: coreRect),
            with: .radialGradient(
                Gradient(colors: [coreColor, baseColor.opacity(particleOpacity * 0.5)]),
                center: CGPoint(x: screenX, y: screenY),
                startRadius: 0,
                endRadius: particle.size * 0.3
            )
        )
    }
    
    // MARK: - Initialization
    
    private func initializeParticles() {
        guard particles.isEmpty else { return }
        particles = (0..<particleCount).map { _ in
            SoulParticle.random(in: .zero)
        }
    }
    
    private func startAnimation() {
        // Animation is driven by TimelineView for particles
        // Progress is controlled externally via binding
    }
}

// MARK: - View Extension for Easy Integration

extension View {
    /// Apply death transition overlay that fades in as progress increases
    /// - Parameters:
    ///   - isActive: Whether the death transition should be shown
    ///   - progress: Animation progress from 0 to 1
    ///   - onComplete: Called when transition reaches completion
    @ViewBuilder
    func deathTransition(
        isActive: Bool,
        progress: Binding<CGFloat>,
        onComplete: (() -> Void)? = nil
    ) -> some View {
        self.overlay {
            if isActive {
                DeathTransitionOverlay(
                    progress: progress,
                    onComplete: onComplete
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Animation Controller

/// Controller for managing death transition animation timing
/// 
/// Usage:
/// ```swift
/// @StateObject private var deathController = DeathTransitionController()
/// 
/// // When player dies:
/// deathController.startTransition {
///     showDeathScreen = true
/// }
/// ```
@MainActor
final class DeathTransitionController: ObservableObject {
    @Published var isActive = false
    @Published var progress: CGFloat = 0
    
    private var animationTask: Task<Void, Never>?
    
    /// Duration of the full transition in seconds
    var transitionDuration: TimeInterval = 2.0
    
    /// Start the death transition animation
    /// - Parameter completion: Called when transition reaches 1.0
    func startTransition(completion: @escaping () -> Void) {
        guard !isActive else { return }
        
        isActive = true
        progress = 0
        
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            let startTime = Date()
            
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let newProgress = min(1.0, elapsed / transitionDuration)
                
                // Use easeInOut curve for smoother feel
                progress = easeInOutCubic(newProgress)
                
                if newProgress >= 1.0 {
                    completion()
                    break
                }
                
                // ~60fps update rate
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
    
    /// Reset the transition state
    func reset() {
        animationTask?.cancel()
        animationTask = nil
        isActive = false
        progress = 0
    }
    
    /// Cubic ease-in-out curve for natural progression
    private func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let p = 2 * t - 2
            return 0.5 * p * p * p + 1
        }
    }
    
    deinit {
        animationTask?.cancel()
    }
}

// MARK: - Animation Constants Extension

extension AnimationConstants {
    
    // MARK: - Death Transition Animations
    
    /// Death overlay fade duration (2 seconds - dramatic)
    static let deathOverlayFadeDuration: TimeInterval = 2.0
    
    /// Death overlay maximum opacity (0.9 - not fully black)
    static let deathOverlayMaxOpacity: CGFloat = 0.9
    
    /// Soul particle count range
    static let deathParticleCountMin: Int = 12
    static let deathParticleCountMax: Int = 20
    
    /// Soul particle rise animation (continuous, ethereal)
    /// No bounce - smooth upward drift
    static let soulParticleRise = Animation.linear(duration: 3.0)
    
    /// Death screen entrance after transition (spring with slight bounce)
    static let deathScreenEntrance = Animation.spring(duration: 0.5, bounce: 0.15)
    
    // MARK: - Death Transition (Reduce Motion)
    
    /// Simple fade for Reduce Motion users
    /// 1.5 seconds - slightly faster since no particle drama
    static let deathFadeReduceMotion = Animation.easeOut(duration: 1.5)
}

// MARK: - Self-Contained Death Transition View

/// A self-contained death transition view that manages its own animation progress.
/// Simply add to view hierarchy when player dies - starts animation automatically.
struct SelfContainedDeathTransition: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        DeathTransitionOverlay(progress: $progress)
            .onAppear {
                // Animate progress from 0 to 1 over 2 seconds
                withAnimation(.easeInOut(duration: 2.0)) {
                    progress = 1.0
                }
            }
    }
}

// MARK: - Preview

#Preview("Death Transition") {
    struct PreviewContainer: View {
        @State private var progress: CGFloat = 0
        @State private var isActive = true
        
        var body: some View {
            ZStack {
                // Fake game background
                LinearGradient(
                    colors: [.gray, .brown],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                VStack {
                    Text("Game Map Here")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                    
                    Button("Trigger Death") {
                        progress = 0
                        isActive = true
                        withAnimation(.linear(duration: 2.5)) {
                            progress = 1.0
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Text("Progress: \(progress, specifier: "%.2f")")
                        .foregroundColor(.white)
                }
                
                if isActive {
                    DeathTransitionOverlay(progress: $progress)
                }
            }
            .ignoresSafeArea()
        }
    }
    
    return PreviewContainer()
}

#Preview("Reduce Motion") {
    struct ReduceMotionPreview: View {
        @State private var progress: CGFloat = 0
        @Environment(\.accessibilityReduceMotion) var reduceMotion
        
        var body: some View {
            ZStack {
                Color.gray
                
                VStack {
                    Text("Reduce Motion: \(reduceMotion ? "ON" : "OFF")")
                        .foregroundColor(.white)
                    
                    Button("Start") {
                        progress = 0
                        withAnimation(.linear(duration: 2.0)) {
                            progress = 1.0
                        }
                    }
                }
                
                DeathTransitionOverlay(progress: $progress)
            }
        }
    }
    
    return ReduceMotionPreview()
}
