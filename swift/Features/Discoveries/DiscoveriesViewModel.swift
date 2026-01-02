//
//  DiscoveriesViewModel.swift
//  nethack
//
//  ViewModel for Discoveries feature - handles state and business logic
//  SWIFTUI-P-001: @Observable for efficient change tracking
//

import SwiftUI
import Observation

@MainActor
@Observable
final class DiscoveriesViewModel {
    // MARK: - Published Properties

    private(set) var categories: [DiscoveryCategory] = []
    private(set) var allItems: [DiscoveryItem] = []

    var searchText: String = "" {
        didSet {
            updateFilteredCategories()
        }
    }

    private(set) var filteredCategories: [DiscoveryCategory] = []

    // Category expansion state
    var expandedCategories: Set<ItemCategory> = []

    // MARK: - Computed Properties

    var totalDiscovered: Int {
        allItems.filter { $0.isDiscovered }.count
    }

    var totalItems: Int {
        allItems.count
    }

    var overallProgress: Double {
        guard totalItems > 0 else { return 0.0 }
        return Double(totalDiscovered) / Double(totalItems)
    }

    var progressText: String {
        "\(totalDiscovered)/\(totalItems)"
    }

    var isSearching: Bool {
        !searchText.isEmpty
    }

    // MARK: - Initialization

    init() {
        // Empty - call loadDiscoveries() after creation
    }

    // MARK: - Public Methods

    /// Load discoveries from NetHack bridge
    func loadDiscoveries(from manager: NetHackGameManager) {
        let discoveries = manager.getDiscoveries()
        allItems = discoveries

        // Group by category
        let grouped = Dictionary(grouping: discoveries) { $0.category }
        categories = ItemCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return DiscoveryCategory(id: category, items: items.sorted { $0.name < $1.name })
        }

        // Initially show all categories
        updateFilteredCategories()

        // Expand categories with discoveries by default
        expandedCategories = Set(
            categories
                .filter { $0.discoveredCount > 0 }
                .map { $0.id }
        )
    }

    /// Toggle category expansion
    func toggleCategory(_ category: ItemCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    /// Check if category is expanded
    func isExpanded(_ category: ItemCategory) -> Bool {
        expandedCategories.contains(category)
    }

    /// Refresh discoveries (call after game state changes)
    func refresh(from manager: NetHackGameManager) {
        loadDiscoveries(from: manager)
    }

    // MARK: - Private Methods

    private func updateFilteredCategories() {
        guard !searchText.isEmpty else {
            filteredCategories = categories
            return
        }

        let lowercasedSearch = searchText.lowercased()
        filteredCategories = categories.compactMap { category in
            let matchingItems = category.items.filter { item in
                item.name.lowercased().contains(lowercasedSearch) ||
                item.appearance.lowercased().contains(lowercasedSearch)
            }

            guard !matchingItems.isEmpty else { return nil }

            return DiscoveryCategory(
                id: category.id,
                items: matchingItems
            )
        }

        // Auto-expand filtered categories
        if !searchText.isEmpty {
            expandedCategories = Set(filteredCategories.map { $0.id })
        }
    }
}
