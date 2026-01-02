import SwiftUI

/// Delete confirmation sheet with iCloud-aware options
/// Shows different options based on sync status:
/// - Synced: Both "Delete from Device" and "Delete Everywhere"
/// - Local only: Single "Delete" option
///
/// Design follows dark roguelike aesthetic with destructive red styling
struct DeleteConfirmationSheet: View {
    let character: CharacterMetadata
    let onDeleteLocal: () -> Void       // Delete from device only
    let onDeleteEverywhere: () -> Void  // Delete from device + iCloud

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isLocalPressed = false
    @State private var isEverywherePressed = false

    private var isSynced: Bool {
        character.syncStatus == .synced
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)

                Text("Delete \"\(character.characterName)\"?")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }

            // Explanation (only if synced)
            if isSynced {
                Text("This character has been synced to iCloud. Choose how to delete:")
                    .font(.system(size: 15))
                    .foregroundColor(.nethackGray600)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Options
            VStack(spacing: 12) {
                // Delete local only (if synced)
                if isSynced {
                    deleteLocalButton
                }

                // Delete everywhere (always shown, different label if not synced)
                deleteEverywhereButton
            }

            // Cancel
            Button("Cancel") {
                dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.nethackAccent)
            .padding(.top, 8)
            .frame(minHeight: 44)  // Apple HIG minimum
        }
        .padding(24)
        .background(Color.nethackGray100)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Delete Local Button

    private var deleteLocalButton: some View {
        Button(action: {
            onDeleteLocal()
            dismiss()
        }) {
            VStack(spacing: 4) {
                Text("Delete from This Device Only")
                    .font(.system(size: 16, weight: .semibold))
                Text("Character stays in iCloud")
                    .font(.system(size: 13))
                    .foregroundColor(.nethackGray600)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.nethackGray200)
            )
            .contentShape(Rectangle())
            .scaleEffect(isLocalPressed ? AnimationConstants.pressScale : 1.0)
            .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isLocalPressed)
        }
        .foregroundColor(.white)
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isLocalPressed = true }
                .onEnded { _ in isLocalPressed = false }
        )
        .accessibilityLabel("Delete from this device only")
        .accessibilityHint("The character will remain in iCloud and can be downloaded again")
    }

    // MARK: - Delete Everywhere Button

    private var deleteEverywhereButton: some View {
        Button(action: {
            onDeleteEverywhere()
            dismiss()
        }) {
            VStack(spacing: 4) {
                Text(isSynced ? "Delete Everywhere" : "Delete Character")
                    .font(.system(size: 16, weight: .semibold))
                Text(isSynced ? "Removes from iCloud too" : "This cannot be undone")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .scaleEffect(isEverywherePressed ? AnimationConstants.pressScale : 1.0)
            .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isEverywherePressed)
        }
        .foregroundColor(.red)
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isEverywherePressed = true }
                .onEnded { _ in isEverywherePressed = false }
        )
        .accessibilityLabel(isSynced ? "Delete everywhere" : "Delete character")
        .accessibilityHint(isSynced ? "Permanently removes the character from this device and iCloud" : "Permanently deletes this character")
    }
}

// MARK: - Preview

#Preview("Delete Synced Character") {
    ZStack {
        Color.black.ignoresSafeArea()

        DeleteConfirmationSheet(
            character: CharacterMetadata(
                characterName: "Valkyrie",
                role: "Valkyrie",
                race: "Human",
                gender: "Female",
                alignment: "Lawful",
                level: 14,
                hp: 87,
                hpmax: 120,
                turns: 5432,
                dungeonLevel: 8,
                lastSaved: "2025-12-30T14:45:00Z",
                createdAt: nil,
                updatedAt: nil,
                syncedAt: Date(),  // Synced
                downloadedAt: nil
            ),
            onDeleteLocal: { print("Delete local") },
            onDeleteEverywhere: { print("Delete everywhere") }
        )
        .frame(maxWidth: 340)
    }
}

#Preview("Delete Local Character") {
    ZStack {
        Color.black.ignoresSafeArea()

        DeleteConfirmationSheet(
            character: CharacterMetadata(
                characterName: "Wizard",
                role: "Wizard",
                race: "Elf",
                gender: "Male",
                alignment: "Neutral",
                level: 5,
                hp: 32,
                hpmax: 45,
                turns: 1200,
                dungeonLevel: 3,
                lastSaved: "2025-12-30T10:30:00Z",
                createdAt: nil,
                updatedAt: nil,
                syncedAt: nil,  // Not synced
                downloadedAt: nil
            ),
            onDeleteLocal: { print("Delete local") },
            onDeleteEverywhere: { print("Delete everywhere") }
        )
        .frame(maxWidth: 340)
    }
}
