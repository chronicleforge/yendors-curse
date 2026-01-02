//
//  DownloadProgressView.swift
//  nethack
//
//  Phase 6: Enhanced download progress with actual percentage and cancel button.
//  Replaces time-based estimate with real iCloudManager.syncProgress.
//
//  Reference: SWIFTUI-A-001 - Spring animations for natural feel
//

import SwiftUI

// MARK: - Download Progress View

/// Full-screen overlay showing download progress with cancel option
struct DownloadProgressView: View {
    let characterName: String
    @ObservedObject var iCloudManager: iCloudStorageManager
    let onCancel: () -> Void
    
    @State private var iconPulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let isPhone = UIDevice.current.userInterfaceIdiom == .phone
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { }  // Prevent tap-through
            
            // Content card
            VStack(spacing: 24) {
                // Cloud icon with animation
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: isPhone ? 40 : 48))
                    .foregroundColor(.blue)
                    .scaleEffect(iconPulse ? 1.1 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: iconPulse
                    )
                    .onAppear {
                        iconPulse = true
                    }
                
                // Title
                Text("Downloading \"\(characterName)\"...")
                    .font(.system(size: isPhone ? 16 : 18, weight: .semibold))
                    .foregroundColor(.white)
                
                // Progress section
                VStack(spacing: 12) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Track
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                            
                            // Fill
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geometry.size.width * iCloudManager.syncProgress))
                                .animation(
                                    reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1),
                                    value: iCloudManager.syncProgress
                                )
                        }
                    }
                    .frame(width: isPhone ? 180 : 220, height: 8)
                    
                    // Progress text
                    Text(progressText)
                        .font(.system(size: isPhone ? 13 : 14, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: isPhone ? 14 : 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                )
                        )
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.nethackGray100)
                    .shadow(color: .black.opacity(0.5), radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Downloading \(characterName), \(progressText)")
        .accessibilityAddTraits(.isModal)
    }
    
    private var progressText: String {
        let percent = Int(iCloudManager.syncProgress * 100)
        
        // Show indeterminate if progress is 0 (still initializing)
        guard percent > 0 else {
            return "Preparing..."
        }
        
        return "\(percent)% complete"
    }
}

// MARK: - Compact Download Indicator

/// Smaller inline progress indicator for use in cards/rows
struct CompactDownloadIndicator: View {
    @ObservedObject var iCloudManager: iCloudStorageManager
    
    var body: some View {
        HStack(spacing: 6) {
            // Animated icon
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 12))
                .foregroundColor(.blue)
            
            // Progress
            if iCloudManager.syncProgress > 0 {
                Text("\(Int(iCloudManager.syncProgress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.blue)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.15))
        )
    }
}

// MARK: - Preview

#Preview("Download Progress") {
    DownloadProgressView(
        characterName: "Valkyrie",
        iCloudManager: {
            let manager = iCloudStorageManager.shared
            return manager
        }(),
        onCancel: { }
    )
    .preferredColorScheme(.dark)
}

#Preview("Compact Indicator") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        CompactDownloadIndicator(
            iCloudManager: iCloudStorageManager.shared
        )
    }
    .preferredColorScheme(.dark)
}
