//
//  OfflineBanner.swift
//  nethack
//
//  Phase 4: Banner shown when iCloud is unavailable.
//  Orange warning styling, dismissible with X button.
//
//  Reference: SWIFTUI-A-003 - Combined transitions for polish
//

import SwiftUI

// MARK: - Offline Banner

/// Banner displayed when iCloud is unavailable
/// Shows at top of character selection screen
struct OfflineBanner: View {
    @ObservedObject var iCloudManager = iCloudStorageManager.shared
    @State private var dismissed = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        // Guard: Only show when iCloud unavailable and not dismissed
        if !iCloudManager.isAvailable && !dismissed {
            HStack(spacing: 12) {
                // Warning icon
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.orange)
                
                // Message content
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Unavailable")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Check your connection. Playing offline.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Dismiss button - 44pt touch target
                Button(action: {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) {
                        dismissed = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("iCloud Unavailable. Check your connection. Playing offline.")
            .accessibilityHint("Double tap to dismiss")
            .accessibilityAddTraits(.isButton)
        }
    }
    
    /// Reset dismissed state (e.g., when returning to screen after iCloud becomes available then unavailable again)
    func reset() {
        dismissed = false
    }
}

// MARK: - Compact Offline Indicator

/// Smaller inline indicator for use in tighter spaces
struct CompactOfflineIndicator: View {
    @ObservedObject var iCloudManager = iCloudStorageManager.shared
    
    var body: some View {
        if !iCloudManager.isAvailable {
            HStack(spacing: 4) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 10))
                Text("Offline")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .accessibilityLabel("Offline mode")
        }
    }
}

// MARK: - Preview

#Preview("Offline Banner") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            OfflineBanner()
                .padding()
            
            Spacer()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Compact Indicator") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        CompactOfflineIndicator()
    }
    .preferredColorScheme(.dark)
}
