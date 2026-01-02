//
//  DiscoveriesModels.swift
//  nethack
//
//  Data models for the Discoveries feature
//

import SwiftUI

// MARK: - Discovery Item

/// Represents a single discoverable item in NetHack
struct DiscoveryItem: Identifiable, Hashable {
    let id: Int32          // NetHack otyp (object type index)
    let name: String       // Full name (e.g., "long sword")
    let appearance: String // Description (e.g., "runed sword")
    let category: ItemCategory
    let isDiscovered: Bool
    let isEncountered: Bool    // Hero has observed such an item at least once
    let isUnique: Bool     // Unique artifacts (e.g., Excalibur)

    /// Display name respects discovery status
    var displayName: String {
        guard !isDiscovered else { return name }
        return appearance.isEmpty ? "Unknown" : appearance
    }

    /// Short category-based icon
    var categoryIcon: String {
        category.icon
    }

    /// Status icon (checkmark, question, star)
    var statusIcon: String {
        guard isDiscovered else { return "questionmark.circle.fill" }
        guard !isEncountered else { return "star.fill" }
        return "checkmark.circle.fill"
    }

    /// Status icon color
    var statusColor: Color {
        guard isDiscovered else { return .gray.opacity(0.4) }
        guard !isEncountered else { return .yellow }
        return .green
    }
}

// MARK: - Discovery Category

/// Groups discoveries by item type with progress tracking
struct DiscoveryCategory: Identifiable {
    let id: ItemCategory
    let items: [DiscoveryItem]

    var name: String { id.pluralName }
    var icon: String { id.icon }
    var color: Color { id.color }

    // Progress calculations
    var discoveredCount: Int {
        items.filter { $0.isDiscovered }.count
    }

    var totalCount: Int {
        items.count
    }

    var progress: Double {
        guard totalCount > 0 else { return 0.0 }
        return Double(discoveredCount) / Double(totalCount)
    }

    var progressText: String {
        "\(discoveredCount)/\(totalCount)"
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}
