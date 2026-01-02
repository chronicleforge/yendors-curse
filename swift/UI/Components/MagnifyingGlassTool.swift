/*
 * MagnifyingGlassTool.swift - Tile Inspection Tool
 *
 * Provides a magnifying glass tool for examining tiles on the map.
 * Combines NetHack's `;` (quick glance) and `:` (detailed look) commands.
 *
 * SWIFTUI REFERENCES:
 * - SWIFTUI-L-001: Z-Index for layering overlay above game
 * - SWIFTUI-L-002: ZStack for independent overlay positioning
 * - SWIFTUI-A-001: Spring animations with bounce: 0.15-0.2
 * - SWIFTUI-A-003: Combined transitions (scale + opacity)
 * - SWIFTUI-A-009: Reduce Motion accessibility (MANDATORY)
 * - SWIFTUI-P-001: @State for tool state management
 * - SWIFTUI-HIG-001: Animation durations 200-400ms
 * - SWIFTUI-HIG-002: Haptic feedback timing
 *
 * Design Philosophy:
 * - Toggle button (tap = activate, tap again = deactivate)
 * - Active state: tapping tiles shows inspection overlay
 * - Inspection overlay: Auto-dismiss after 3 seconds OR tap to dismiss
 * - Visual feedback: Active state shows tool highlight
 */

import SwiftUI

// MARK: - Unified Tool Button Style

/// Reusable button style for tool buttons (Inspect, Equip, Inventory)
struct ToolButton: View {
    let icon: String
    let activeIcon: String?
    let label: String
    let isActive: Bool
    let accentColor: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    init(
        icon: String,
        activeIcon: String? = nil,
        label: String,
        isActive: Bool = false,
        accentColor: Color = .nethackSuccess,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.activeIcon = activeIcon
        self.label = label
        self.isActive = isActive
        self.accentColor = accentColor
        self.action = action
    }

    // Match CommandGroupBar button sizes (updated)
    private var buttonWidth: CGFloat { isPhone ? 54 : 66 }
    private var buttonHeight: CGFloat { isPhone ? 52 : 60 }
    private var iconSize: CGFloat { isPhone ? 20 : 24 }

    var body: some View {
        Button(action: action) {
            // Match CommandGroupButton: VStack(spacing: 2)
            VStack(spacing: 2) {
                Image(systemName: isActive ? (activeIcon ?? icon) : icon)
                    // Match CommandGroupButton: .bold weight
                    .font(.system(size: iconSize, weight: .bold))
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .foregroundColor(isActive ? accentColor : .nethackGray700)

                Text(label)
                    // Match CommandGroupButton: 9:10 sizes, .semibold weight
                    .font(.system(size: isPhone ? 9 : 10, weight: .semibold))
                    .foregroundColor(isActive ? accentColor : .nethackGray900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            // Match CommandGroupButton: separate background and overlay
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isActive ? accentColor : Color.nethackGray700.opacity(0.4),
                        lineWidth: isActive ? 3 : 2
                    )
            )
            .shadow(
                color: isActive ? accentColor.opacity(0.4) : Color.black.opacity(0.3),
                radius: isActive ? 8 : 4,
                x: 0,
                y: 2
            )
        }
        // Match CommandGroupButton: Use CommandButtonStyle for consistent press animation (0.92 scale)
        .buttonStyle(CommandButtonStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }
}

// MARK: - Magnifying Glass Button

struct MagnifyingGlassButton: View {
    @Binding var isActive: Bool
    let onToggle: () -> Void

    var body: some View {
        ToolButton(
            icon: "magnifyingglass.circle",
            activeIcon: "magnifyingglass.circle.fill",
            label: "Inspect",
            isActive: isActive,
            accentColor: .nethackSuccess
        ) {
            isActive.toggle()
            onToggle()
        }
        .accessibilityHint("Tap to toggle tile inspection mode")
    }
}

// MARK: - Equip Button

struct EquipButton: View {
    let onTap: () -> Void

    var body: some View {
        ToolButton(
            icon: "person.crop.rectangle",
            label: "Equip",
            accentColor: .cyan
        ) {
            HapticManager.shared.tap()
            onTap()
        }
        .accessibilityHint("View and manage equipped items")
    }
}

// MARK: - Inventory Button

struct InventoryButton: View {
    let onTap: () -> Void

    var body: some View {
        ToolButton(
            icon: "bag",
            label: "Inventory",
            accentColor: .orange
        ) {
            HapticManager.shared.tap()
            onTap()
        }
        .accessibilityHint("Open inventory")
    }
}

// MARK: - Inspection Overlay Card

struct InspectionOverlayCard: View {
    let tile: (x: Int, y: Int)
    let messages: [String]
    let screenPos: CGPoint
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion  // SWIFTUI-A-009
    @State private var opacity: Double = 1.0

    // Device detection for iPhone-specific sizing
    private let isPhone = ScalingEnvironment.isPhone

    // SWIFTUI-A-001: Professional spring animation
    private var cardAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)
    }

    var body: some View {
        let cardWidth = ScalingEnvironment.UIScale.inspectionCardWidth(isPhone: isPhone)
        let fontSize: CGFloat = isPhone ? 11 : 13
        let headerFontSize: CGFloat = isPhone ? 12 : 14
        let iconSize: CGFloat = isPhone ? 16 : 18

        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: isPhone ? 6 : 8) {
                // Header with tile coordinates
                HStack(spacing: isPhone ? 6 : 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: headerFontSize - 2, weight: .semibold))
                        .foregroundColor(.nethackSuccess)  // LCH: Green

                    Text("Inspection")
                        .font(.system(size: headerFontSize, weight: .semibold))
                        .foregroundColor(.nethackGray900)  // LCH: Near-white

                    Spacer()

                    // Dismiss button
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: iconSize))
                            .foregroundColor(.nethackGray600)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .background(Color.white.opacity(0.2))

                // Messages content (multiple lines)
                VStack(alignment: .leading, spacing: 4) {
                    // CRITICAL FIX (SWIFTUI-M-004): Use unique IDs for ForEach
                    // BEFORE: ForEach(messages, id: \.self) caused duplicate ID errors
                    // when same message appeared multiple times (e.g. "You see: nothing special")
                    // AFTER: Use array index as unique ID - each message position is unique
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        Text(message)
                            .font(.system(size: fontSize))
                            .foregroundColor(.nethackGray900)  // LCH: Near-white
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .lineLimit(nil)
            }
            .padding(isPhone ? 10 : 12)
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.nethackSuccess.opacity(0.4), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
            )
            .opacity(opacity)
            .position(calculatePosition(in: geometry.size))
            // SWIFTUI-A-003: Combined transitions
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            .onTapGesture {
                onDismiss()
            }
        }
        .zIndex(50)  // SWIFTUI-L-001: Above game, below action wheel
        .onAppear {
            // Start fade-out animation after 2.5 seconds (before auto-dismiss)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 0.6
                }
            }
        }
    }

    // Calculate position to keep overlay on screen
    private func calculatePosition(in size: CGSize) -> CGPoint {
        var x = screenPos.x
        var y = screenPos.y

        // Keep overlay on screen with device-aware margin
        let margin: CGFloat = isPhone ? 12 : 20
        let cardWidth = ScalingEnvironment.UIScale.inspectionCardWidth(isPhone: isPhone)
        let cardHeight: CGFloat = isPhone ? 80 : 100  // Approximate height

        // Horizontal bounds
        if x - cardWidth/2 < margin {
            x = margin + cardWidth/2
        } else if x + cardWidth/2 > size.width - margin {
            x = size.width - margin - cardWidth/2
        }

        // Vertical bounds (prefer above tile)
        let preferredY = screenPos.y - cardHeight - 40  // 40pt above tile
        if preferredY < margin {
            // Not enough space above, place below
            y = screenPos.y + cardHeight + 40
        } else {
            y = preferredY + cardHeight/2
        }

        // Final bounds check
        if y - cardHeight/2 < margin {
            y = margin + cardHeight/2
        } else if y + cardHeight/2 > size.height - margin {
            y = size.height - margin - cardHeight/2
        }

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Preview

#if DEBUG
struct MagnifyingGlassTool_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    MagnifyingGlassButton(isActive: .constant(false), onToggle: {})
                    MagnifyingGlassButton(isActive: .constant(true), onToggle: {})

                    Spacer()
                }

                Spacer()
            }

            // Preview overlay
            InspectionOverlayCard(
                tile: (x: 10, y: 5),
                messages: ["You see a long sword here.", "The floor is made of stone."],
                screenPos: CGPoint(x: 300, y: 200),
                onDismiss: {}
            )
        }
        .preferredColorScheme(.dark)
    }
}
#endif
