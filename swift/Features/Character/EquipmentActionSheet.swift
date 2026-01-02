//
//  EquipmentActionSheet.swift
//  nethack
//
//  Action sheet for equipped items - allows Remove, Info, and shows cursed warnings.
//

import SwiftUI

/// Action sheet shown when tapping an equipped item in the paper doll
struct EquipmentActionSheet: View {
    let slot: EquipmentSlot
    let item: EquippedItem
    let status: CharacterStatus
    let onRemove: () -> Void
    let onInfo: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var canRemoveResult: (canRemove: Bool, reason: String?) {
        status.canRemove(slot: slot)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header with item name
            header

            Divider()
                .background(Color.white.opacity(0.2))

            // Actions
            VStack(spacing: 12) {
                // Remove button
                removeButton

                // Info button
                infoButton
            }

            // Cancel button
            Button(action: onDismiss) {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            // Slot icon with BUC indicator
            ZStack(alignment: .topTrailing) {
                Image(systemName: slot.icon)
                    .font(.title)
                    .foregroundColor(slot.color)
                    .frame(width: 50, height: 50)
                    .background(slot.color.opacity(0.2))
                    .clipShape(Circle())

                // BUC indicator
                if item.isCursed {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                } else if item.isBlessed {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }

            // Item name
            Text(item.name)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Slot name
            Text(slot.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Remove Button

    private var removeButton: some View {
        let result = canRemoveResult

        return Button(action: {
            guard result.canRemove else { return }
            HapticManager.shared.buttonPress()
            onRemove()
        }) {
            HStack {
                Image(systemName: result.canRemove ? "minus.circle.fill" : "lock.fill")
                    .foregroundColor(result.canRemove ? .red : .gray)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove")
                        .font(.headline)
                        .foregroundColor(result.canRemove ? .primary : .secondary)

                    if let reason = result.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                if result.canRemove {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(result.canRemove ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(!result.canRemove)
    }

    // MARK: - Info Button

    private var infoButton: some View {
        Button(action: {
            HapticManager.shared.tap()
            onInfo()
        }) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                Text("Item Details")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EquipmentActionSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            EquipmentActionSheet(
                slot: .bodyArmor,
                item: EquippedItem(
                    slot: .bodyArmor,
                    name: "+2 mithril-coat",
                    isCursed: false,
                    isBlessed: true
                ),
                status: CharacterStatus(
                    identity: .empty,
                    equipment: [],
                    hungerState: 0,
                    hungerName: "",
                    encumbrance: 0,
                    encumbranceName: "",
                    conditions: 0,
                    isPolymorphed: false,
                    polymorphForm: nil,
                    polymorphTurnsLeft: 0,
                    isWeaponWelded: false,
                    leftRingAvailable: true,
                    rightRingAvailable: true
                ),
                onRemove: { print("Remove") },
                onInfo: { print("Info") },
                onDismiss: { print("Dismiss") }
            )
        }
    }
}
#endif
