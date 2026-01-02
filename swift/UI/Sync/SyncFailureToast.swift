//
//  SyncFailureToast.swift
//  nethack
//
//  Phase 3: Non-blocking toast for upload/download failures with retry action.
//  Bottom-anchored, auto-dismiss after 10 seconds.
//
//  Reference: SWIFTUI-A-003 - Combined transitions for polish
//

import SwiftUI

// MARK: - Sync Failure Model

/// Represents a sync failure that can be retried
struct SyncFailure: Identifiable {
    let id = UUID()
    
    enum FailureType: Equatable {
        case upload(characterName: String)
        case download(characterName: String)
        
        var title: String {
            switch self {
            case .upload: return "Upload Failed"
            case .download: return "Download Failed"
            }
        }
        
        var message: String {
            switch self {
            case .upload(let name):
                return "\"\(name)\" couldn't sync. Your save is safe locally."
            case .download(let name):
                return "\"\(name)\" couldn't download. Check your connection."
            }
        }
        
        var icon: String {
            switch self {
            case .upload: return "arrow.up.circle.fill"
            case .download: return "icloud.and.arrow.down.fill"
            }
        }
    }
    
    let type: FailureType
    let retryAction: () async throws -> Void
    let timestamp: Date = Date()
    
    static func == (lhs: SyncFailure, rhs: SyncFailure) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sync Failure Toast View

/// Non-blocking bottom toast showing sync failure with retry option
struct SyncFailureToast: View {
    let failure: SyncFailure
    let onRetry: () async -> Void
    let onDismiss: () -> Void
    
    @State private var isRetrying = false
    @State private var autoDismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let autoDismissDelay: TimeInterval = 10.0
    
    var body: some View {
        HStack(spacing: 12) {
            // Failure icon
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
            
            // Message content
            VStack(alignment: .leading, spacing: 2) {
                Text(failure.type.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(failure.type.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer(minLength: 8)
            
            // Retry button
            Button(action: handleRetry) {
                Group {
                    if isRetrying {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Retry")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .frame(minWidth: 50)
            }
            .foregroundColor(.nethackAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.nethackAccent.opacity(0.2))
            )
            .disabled(isRetrying)
            
            // Dismiss button
            Button(action: {
                cancelAutoDismiss()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 28, height: 28)
            }
            .contentShape(Circle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.nethackGray200)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            startAutoDismiss()
        }
        .onDisappear {
            cancelAutoDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(failure.type.title). \(failure.type.message)")
        .accessibilityHint("Double tap retry button to try again, or swipe to dismiss")
    }
    
    // MARK: - Actions
    
    private func handleRetry() {
        cancelAutoDismiss()
        isRetrying = true
        
        Task {
            await onRetry()
            await MainActor.run {
                isRetrying = false
                onDismiss()
            }
        }
    }
    
    private func startAutoDismiss() {
        autoDismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onDismiss()
            }
        }
    }
    
    private func cancelAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
}

// MARK: - Sync Failure Toast Container

/// Container that manages multiple failure toasts with stacking
struct SyncFailureToastContainer: View {
    @Binding var failures: [SyncFailure]
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(failures) { failure in
                SyncFailureToast(
                    failure: failure,
                    onRetry: {
                        do {
                            try await failure.retryAction()
                        } catch {
                            print("[SyncFailure] Retry failed: \(error)")
                        }
                    },
                    onDismiss: {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) {
                            failures.removeAll { $0.id == failure.id }
                        }
                    }
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Preview

#Preview("Single Failure") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            SyncFailureToast(
                failure: SyncFailure(
                    type: .upload(characterName: "Valkyrie"),
                    retryAction: {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                ),
                onRetry: { },
                onDismiss: { }
            )
            .padding()
        }
    }
}

#Preview("Download Failure") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            SyncFailureToast(
                failure: SyncFailure(
                    type: .download(characterName: "Wizard"),
                    retryAction: { }
                ),
                onRetry: { },
                onDismiss: { }
            )
            .padding()
        }
    }
}
