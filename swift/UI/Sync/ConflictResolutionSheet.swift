//
//  ConflictResolutionSheet.swift
//  nethack
//
//  Phase 5: Sheet for resolving sync conflicts between local and cloud versions.
//  Side-by-side version comparison with "Keep Both (Rename)" option.
//
//  Reference: SWIFTUI-A-003 - Combined transitions for polish
//

import SwiftUI

// MARK: - Conflict Info

/// Information about a sync conflict
struct ConflictInfo: Identifiable {
    let id = UUID()
    let characterName: String
    let localMetadata: CharacterMetadata
    let cloudMetadata: CharacterMetadata
}

// MARK: - Conflict Resolution Sheet

/// Sheet for resolving sync conflicts between local and cloud versions
struct ConflictResolutionSheet: View {
    let characterName: String
    let localMetadata: CharacterMetadata
    let cloudMetadata: CharacterMetadata
    let onKeepLocal: () async -> Void
    let onKeepCloud: () async -> Void
    let onKeepBoth: () async -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var isProcessing = false
    @State private var selectedOption: ConflictOption?
    
    private enum ConflictOption {
        case local, cloud, both
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerSection
            
            // Version comparison cards
            // CRITICAL-3 FIX: Pass both metadata for diff calculation
            HStack(spacing: 16) {
                // Local version
                ConflictVersionCard(
                    title: "This Device",
                    icon: "iphone",
                    metadata: localMetadata,
                    otherMetadata: cloudMetadata,
                    isSelected: selectedOption == .local,
                    isProcessing: isProcessing && selectedOption == .local,
                    onSelect: {
                        handleSelection(.local)
                    }
                )

                // Cloud version
                ConflictVersionCard(
                    title: "iCloud",
                    icon: "icloud.fill",
                    metadata: cloudMetadata,
                    otherMetadata: localMetadata,
                    isSelected: selectedOption == .cloud,
                    isProcessing: isProcessing && selectedOption == .cloud,
                    onSelect: {
                        handleSelection(.cloud)
                    }
                )
            }
            .padding(.horizontal, 8)
            
            // Keep Both option
            Button(action: {
                handleSelection(.both)
            }) {
                HStack(spacing: 8) {
                    if isProcessing && selectedOption == .both {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                    }
                    
                    Text("Keep Both (Rename Conflict)")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }
            .disabled(isProcessing)
            
            // Cancel button
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.nethackGray500)
            .padding(.top, 8)
            .disabled(isProcessing)
        }
        .padding(24)
        .background(Color.nethackGray100)
        .accessibilityElement(children: .contain)
    }
    
    // MARK: - Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            // Warning icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Sync Conflict")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Text("\"\(characterName)\" was modified on multiple devices.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Actions
    
    private func handleSelection(_ option: ConflictOption) {
        guard !isProcessing else { return }
        
        selectedOption = option
        isProcessing = true
        
        Task {
            switch option {
            case .local:
                await onKeepLocal()
            case .cloud:
                await onKeepCloud()
            case .both:
                await onKeepBoth()
            }
            
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
}

// MARK: - Conflict Version Card

/// Card showing details of a version (local or cloud)
/// CRITICAL-3 FIX: Shows diff compared to other version and uses turn count as progress indicator
struct ConflictVersionCard: View {
    let title: String
    let icon: String
    let metadata: CharacterMetadata
    let otherMetadata: CharacterMetadata  // For diff calculation
    let isSelected: Bool
    let isProcessing: Bool
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True if this version has more progress (more turns = more gameplay)
    private var isRecommended: Bool {
        metadata.turns > otherMetadata.turns
    }

    /// Difference in turns (positive = this version has more)
    private var turnsDiff: Int {
        metadata.turns - otherMetadata.turns
    }

    /// Difference in level
    private var levelDiff: Int {
        metadata.level - otherMetadata.level
    }

    /// Difference in HP
    private var hpDiff: Int {
        metadata.hp - otherMetadata.hp
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with recommendation badge
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.nethackAccent)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    if isRecommended {
                        // CRITICAL-3: Recommend based on turn count, not timestamp
                        Text("More Progress")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                            )
                    }

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .nethackAccent))
                            .scaleEffect(0.7)
                    }
                }

                // Stats with diffs
                VStack(alignment: .leading, spacing: 6) {
                    // Level with diff
                    HStack {
                        Text("Lv \(metadata.level) \(metadata.role)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)

                        if levelDiff != 0 {
                            diffBadge(value: levelDiff, label: "lv")
                        }
                    }

                    HStack(spacing: 12) {
                        // HP with diff
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text("\(metadata.hp)/\(metadata.hpmax)")
                                .font(.system(size: 13, design: .monospaced))

                            if hpDiff != 0 {
                                diffBadge(value: hpDiff, label: "")
                            }
                        }

                        // Dungeon level
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 10))
                                .foregroundColor(.cyan)
                            Text("Dlvl:\(metadata.dungeonLevel)")
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }
                    .foregroundColor(.white.opacity(0.8))

                    // CRITICAL-3: Turn count is the reliable progress indicator (not affected by clock skew)
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("\(metadata.turns) turns")
                            .font(.system(size: 12, design: .monospaced))

                        if turnsDiff != 0 {
                            diffBadge(value: turnsDiff, label: "")
                        }
                    }
                    .foregroundColor(.white.opacity(0.7))

                    // Last saved (informational only, not used for recommendation)
                    Text("Saved: \(formattedDate)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }

                // Select button
                HStack {
                    Spacer()
                    Text(isRecommended ? "Keep This Version ✓" : "Keep This Version")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isRecommended ? Color.green.opacity(0.8) : (isSelected ? Color.nethackAccent : Color.nethackAccent.opacity(0.6)))
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.nethackGray200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isRecommended ? Color.green.opacity(0.5) : (isSelected ? Color.nethackAccent : Color.white.opacity(0.1)),
                                lineWidth: isRecommended ? 2 : (isSelected ? 2 : 1)
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel("\(title) version: Level \(metadata.level) \(metadata.role), \(metadata.turns) turns, \(isRecommended ? "recommended" : "")")
        .accessibilityHint("Double tap to keep this version")
    }

    /// Badge showing difference (+X or -X)
    @ViewBuilder
    private func diffBadge(value: Int, label: String) -> some View {
        let isPositive = value > 0
        Text("\(isPositive ? "+" : "")\(value)\(label)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(isPositive ? .green : .red)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((isPositive ? Color.green : Color.red).opacity(0.2))
            )
    }

    private var formattedDate: String {
        // Parse ISO 8601 date and format for display
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: metadata.lastSaved) else {
            return metadata.lastSaved
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview("Conflict Resolution") {
    let localMetadata = CharacterMetadata(
        characterName: "Valkyrie",
        role: "Valkyrie",
        race: "Human",
        gender: "Female",
        alignment: "Neutral",
        level: 14,
        hp: 87,
        hpmax: 120,
        turns: 15234,
        dungeonLevel: 8,
        lastSaved: "2025-12-30T14:45:00Z"
    )
    
    let cloudMetadata = CharacterMetadata(
        characterName: "Valkyrie",
        role: "Valkyrie",
        race: "Human",
        gender: "Female",
        alignment: "Neutral",
        level: 12,
        hp: 65,
        hpmax: 98,
        turns: 12100,
        dungeonLevel: 6,
        lastSaved: "2025-12-29T11:30:00Z"
    )
    
    return ConflictResolutionSheet(
        characterName: "Valkyrie",
        localMetadata: localMetadata,
        cloudMetadata: cloudMetadata,
        onKeepLocal: { },
        onKeepCloud: { },
        onKeepBoth: { }
    )
    .preferredColorScheme(.dark)
}
