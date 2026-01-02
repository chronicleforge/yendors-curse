//
//  DiscoveryCategorySection.swift
//  nethack
//
//  Expandable category section for discoveries
//  SWIFTUI-A-003: Combined transitions
//  SWIFTUI-A-009: Reduce Motion support
//

import SwiftUI

struct DiscoveryCategorySection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let category: DiscoveryCategory
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header (tappable)
            categoryHeader
                .contentShape(Rectangle()) // SWIFTUI-M-003
                .onTapGesture {
                    onToggle()
                }

            // Items (expandable)
            if isExpanded {
                itemsList
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.95, anchor: .top)
                                .combined(with: .opacity)
                    ) // SWIFTUI-A-003
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Category Header

    private var categoryHeader: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(category.color)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(category.color.opacity(0.2))
                )

            // Category name
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(duration: 0.3, bounce: 0.2),
                    value: isExpanded
                ) // SWIFTUI-A-001
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 44) // SWIFTUI-HIG-003
    }

    // MARK: - Items List

    private var itemsList: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            ForEach(category.items) { item in
                DiscoveryItemRow(item: item)

                if item != category.items.last {
                    Divider()
                        .padding(.horizontal, 56) // Indent dividers
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Circular Progress View

private struct CircularProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 3)

            // Progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Percentage text
            Text("\(Int(progress * 100))")
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
