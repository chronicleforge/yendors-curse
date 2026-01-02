//
//  DiscoveryItemBadge.swift
//  nethack
//
//  Small badge overlay showing discovery status for inventory items
//  Can be used in inventory views to show which items have been discovered
//

import SwiftUI

struct DiscoveryItemBadge: View {
    let isDiscovered: Bool
    let isEncountered: Bool

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.black.opacity(0.7))
                .frame(width: 20, height: 20)

            // Status icon
            Image(systemName: statusIcon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(statusColor)
        }
        .accessibilityLabel(isDiscovered ? "Discovered" : "Unknown")
    }

    // MARK: - Computed Properties

    private var statusIcon: String {
        guard isDiscovered else { return "questionmark" }
        guard !isEncountered else { return "star.fill" }
        return "checkmark"
    }

    private var statusColor: Color {
        guard isDiscovered else { return .gray }
        guard !isEncountered else { return .yellow }
        return .green
    }
}

// MARK: - Preview Helper

extension DiscoveryItemBadge {
    static var discovered: DiscoveryItemBadge {
        DiscoveryItemBadge(isDiscovered: true, isEncountered: false)
    }

    static var preDiscovered: DiscoveryItemBadge {
        DiscoveryItemBadge(isDiscovered: true, isEncountered: true)
    }

    static var unknown: DiscoveryItemBadge {
        DiscoveryItemBadge(isDiscovered: false, isEncountered: false)
    }
}

// MARK: - View Extension

extension View {
    /// Add a discovery badge overlay to any view
    func discoveryBadge(isDiscovered: Bool, isEncountered: Bool = false) -> some View {
        self.overlay(alignment: .topTrailing) {
            DiscoveryItemBadge(
                isDiscovered: isDiscovered,
                isEncountered: isEncountered
            )
            .offset(x: 4, y: -4)
        }
    }
}
