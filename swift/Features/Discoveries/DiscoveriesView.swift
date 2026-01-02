//
//  DiscoveriesView.swift
//  nethack
//
//  Main discoveries screen showing all discoverable items
//  SWIFTUI-L-002: ZStack for overlays
//  SWIFTUI-A-001: Spring animations with bounce 0.15-0.2
//  SWIFTUI-A-009: Reduce Motion support (MANDATORY)
//

import SwiftUI

struct DiscoveriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let gameManager: NetHackGameManager
    @State private var viewModel = DiscoveriesViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                // Material blur
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection

                        // Search bar
                        searchBar

                        // Categories
                        categoriesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Discoveries")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
        }
        .task {
            viewModel.loadDiscoveries(from: gameManager)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.yellow)

            Text("Your Discoveries")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search discoveries...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.filteredCategories) { category in
                DiscoveryCategorySection(
                    category: category,
                    isExpanded: viewModel.isExpanded(category.id)
                ) {
                    withAnimation(animation) {
                        viewModel.toggleCategory(category.id)
                    }
                }
            }
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle()) // SWIFTUI-M-003
        }
        .frame(minWidth: 44, minHeight: 44) // SWIFTUI-HIG-003: 44pt touch target
    }

    // MARK: - Animation

    private var animation: Animation? {
        reduceMotion
            ? nil
            : .spring(duration: 0.35, bounce: 0.2) // SWIFTUI-A-001
    }
}
