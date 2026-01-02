//
//  DiscoveryItemRow.swift
//  nethack
//
//  Row view for a single discovery item
//  Shows discovered items clearly, blurs undiscovered ones
//

import SwiftUI

struct DiscoveryItemRow: View {
    let item: DiscoveryItem

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: item.statusIcon)
                .font(.title3)
                .foregroundStyle(item.statusColor)
                .frame(width: 28, height: 28)

            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .foregroundStyle(item.isDiscovered ? .primary : .secondary)
                    .blur(radius: item.isDiscovered ? 0 : 2) // Blur undiscovered

                if item.isDiscovered && !item.appearance.isEmpty && item.appearance != item.name {
                    Text("(\(item.appearance))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Pre-discovered badge
            if item.isEncountered {
                preDicoveredBadge
            }

            // Category icon
            Image(systemName: item.categoryIcon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle()) // SWIFTUI-M-003
        .grayscale(item.isDiscovered ? 0 : 0.8) // Desaturate undiscovered
        .opacity(item.isDiscovered ? 1.0 : 0.6) // Dim undiscovered
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pre-Discovered Badge

    private var preDicoveredBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2)

            Text("Known")
                .font(.caption2.bold())
        }
        .foregroundStyle(.yellow)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.yellow.opacity(0.2))
        )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if item.isDiscovered {
            return "\(item.name). \(item.isEncountered ? "Pre-discovered. " : "")Discovered."
        } else {
            return "\(item.displayName). Not yet discovered."
        }
    }
}
