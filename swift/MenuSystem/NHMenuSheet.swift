import SwiftUI

// MARK: - NHMenuSheet
/// Premium glass-morphic menu sheet for NetHack
/// Handles PICK_NONE, PICK_ONE, and PICK_ANY modes
/// Redesigned to match ItemSelectionSheet style
struct NHMenuSheet: View {
    let context: NHMenuContext
    let onSelect: ([NHMenuSelection]) -> Void

    @State private var selections: Set<String> = []
    @State private var hasAppeared = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone
    private let accentColor = Color.nethackAccent

    // MARK: - Init

    init(context: NHMenuContext, onSelect: @escaping ([NHMenuSelection]) -> Void) {
        self.context = context
        self.onSelect = onSelect
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Compact inline header
            compactHeader

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)

            // Content
            if context.hasItems {
                itemList
            } else {
                compactEmptyState
            }

            // Footer (PICK_ANY only)
            if context.pickMode == .any {
                // Thin separator before footer
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)

                compactFooter
            }
        }
        .frame(maxWidth: isPhone ? 340 : 420)
        .background(sheetBackground)
        .clipShape(RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
        .transition(sheetTransition)
        .animation(reduceMotion ? nil : AnimationConstants.sheetAppear, value: hasAppeared)
        .onAppear {
            withAnimation(reduceMotion ? nil : AnimationConstants.sheetAppear) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hasAppeared)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(spacing: isPhone ? 6 : 10) {
            // Icon in colored circle
            if let iconName = context.icon {
                Image(systemName: iconName)
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                    .background(
                        Circle()
                            .fill(accentColor.opacity(0.2))
                    )
            }

            // Title
            Text(context.prompt)
                .font(.system(size: isPhone ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Item count pill
            if context.hasItems {
                Text("\(context.items.filter { !$0.isHeading }.count)")
                    .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.3))
                    )
            }

            // Close button (PICK_NONE and PICK_ONE)
            if context.pickMode != .any {
                CompactCloseButton(reduceMotion: reduceMotion) {
                    HapticManager.shared.tap()
                    handleDismiss()
                }
            }
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .padding(.vertical, isPhone ? 6 : 8)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: isPhone ? 2 : 4) {
                ForEach(Array(context.items.enumerated()), id: \.element.id) { index, item in
                    if item.isHeading {
                        // Section header
                        HStack(spacing: 4) {
                            Text(item.text)
                                .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .padding(.top, index == 0 ? 0 : 8)
                        .padding(.bottom, 2)
                    } else {
                        CompactMenuRow(
                            item: item,
                            pickMode: context.pickMode,
                            isSelected: selections.contains(item.id),
                            accentColor: accentColor,
                            index: index,
                            reduceMotion: reduceMotion,
                            onTap: { handleItemTap(item) }
                        )
                    }
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 6 : 10)
        }
        .frame(maxHeight: isPhone ? 350 : 450)
    }

    // MARK: - Compact Empty State

    private var compactEmptyState: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: isPhone ? 18 : 22))
                    .foregroundColor(.white.opacity(0.25))
                    .emptyStateIconAnimation()

                Text("Nothing to show")
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isPhone ? 16 : 24)
        .emptyStateEntrance(isVisible: hasAppeared, reduceMotion: reduceMotion)
    }

    // MARK: - Compact Footer (PICK_ANY)

    private var compactFooter: some View {
        HStack(spacing: isPhone ? 8 : 12) {
            // Selection count
            Text(selectionText)
                .font(.system(size: isPhone ? 11 : 13))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            // Cancel button
            Button {
                HapticManager.shared.tap()
                handleCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: isPhone ? 12 : 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, isPhone ? 12 : 16)
                    .padding(.vertical, isPhone ? 6 : 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            // Done button
            Button {
                HapticManager.shared.success()
                handleConfirm()
            } label: {
                Text("Done")
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(selections.isEmpty ? .white.opacity(0.4) : .white)
                    .padding(.horizontal, isPhone ? 16 : 20)
                    .padding(.vertical, isPhone ? 6 : 8)
                    .background(
                        Capsule()
                            .fill(selections.isEmpty ? Color.white.opacity(0.1) : accentColor)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selections.isEmpty)
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .padding(.vertical, isPhone ? 8 : 10)
    }

    private var selectionText: String {
        switch selections.count {
        case 0: return "None selected"
        case 1: return "1 selected"
        default: return "\(selections.count) selected"
        }
    }

    // MARK: - Sheet Background (Glass-morphic)

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 12 : 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.25),
                                Color.white.opacity(0.08),
                                accentColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    // MARK: - Sheet Transition

    private var sheetTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : AnimationConstants.sheetAppearTransition
    }

    // MARK: - Actions

    private func handleItemTap(_ item: NHMenuItem) {
        guard item.isSelectable else { return }

        switch context.pickMode {
        case .none:
            // No action for display-only
            break

        case .one:
            // Single selection - select and dismiss immediately
            HapticManager.shared.selection()
            let selection = NHMenuSelection(item: item, count: -1)
            onSelect([selection])
            dismiss()

        case .any:
            // Toggle selection
            HapticManager.shared.tap()
            if selections.contains(item.id) {
                selections.remove(item.id)
            } else {
                selections.insert(item.id)
            }
        }
    }

    private func handleCancel() {
        onSelect([])
        dismiss()
    }

    private func handleConfirm() {
        let selectedItems = context.items.filter { selections.contains($0.id) }
        let menuSelections = selectedItems.map { NHMenuSelection(item: $0, count: -1) }
        onSelect(menuSelections)
        dismiss()
    }

    private func handleDismiss() {
        onSelect([])
        dismiss()
    }
}

// MARK: - Compact Menu Row

/// Compact pill-shaped row for menu items (matches ItemPill design)
private struct CompactMenuRow: View {
    let item: NHMenuItem
    let pickMode: NHPickMode
    let isSelected: Bool
    let accentColor: Color
    let index: Int
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var isConfirming = false
    @State private var hasAppeared = false

    private let isPhone = ScalingEnvironment.isPhone
    private var pillHeight: CGFloat { isPhone ? 44 : 48 }

    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }

    var body: some View {
        Button {
            guard item.isSelectable, !isConfirming else { return }

            if pickMode == .one {
                isConfirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onTap()
                }
            } else {
                onTap()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Checkbox (PICK_ANY only)
                if pickMode == .any && item.isSelectable {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: isPhone ? 16 : 18))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.4))
                        .frame(width: isPhone ? 24 : 28)
                        .animation(reduceMotion ? nil : .spring(duration: 0.15, bounce: 0.1), value: isSelected)
                }

                // Selector badge (if present)
                if let selector = item.selector {
                    Text(String(selector))
                        .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(item.isSelectable ? accentColor : Color.white.opacity(0.2))
                        )
                }

                // Item text
                Text(item.text)
                    .font(.system(size: isPhone ? 11 : 13, weight: item.isBold ? .semibold : .medium))
                    .foregroundColor(item.isSelectable ? .white.opacity(0.9) : .white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                // Count badge (if > 1)
                if item.count > 1 {
                    Text("\u{00D7}\(item.count)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isPhone ? 5 : 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }

                // Selection indicator (PICK_ONE)
                if pickMode == .one && item.isSelectable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, isPhone ? 8 : 10)
            .frame(height: pillHeight)
            .background(pillBackground)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed, isDisabled: !item.isSelectable))
        .disabled(!item.isSelectable && pickMode != .none)
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
    }

    private var pillBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }
            if isPressed { return 0.12 }
            if isSelected && pickMode == .any { return 0.15 }
            return 0.05
        }()

        let borderColor: Color = {
            if isConfirming { return accentColor.opacity(0.6) }
            if isSelected && pickMode == .any { return accentColor.opacity(0.4) }
            return .white.opacity(0.1)
        }()

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: isConfirming ? 2 : 0.5)
            )
    }
}

// MARK: - Compact Close Button

/// Animated close button matching ItemSelectionSheet style
private struct CompactCloseButton: View {
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var isPressed = false
    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "xmark")
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isPressed ? 0.2 : 0.1))
                )
                .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
    }
}

// MARK: - Pressable Button Style (allows scrolling)

/// Button style that tracks press state without blocking scroll gestures
private struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                guard !isDisabled else { return }
                isPressed = newValue
            }
    }
}

// MARK: - Preview

#Preview("PICK_NONE - Help") {
    ZStack {
        // Dark game background
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        NHMenuSheet(
            context: NHMenuContext(
                prompt: "Command Help",
                pickMode: .none,
                items: [
                    .heading("Movement"),
                    .item("Move north", selector: "k"),
                    .item("Move south", selector: "j"),
                    .item("Move east", selector: "l"),
                    .item("Move west", selector: "h"),
                    .heading("Actions"),
                    .item("Pick up", selector: ","),
                    .item("Drop", selector: "d"),
                    .item("Inventory", selector: "i"),
                ],
                icon: "questionmark.circle.fill"
            ),
            onSelect: { _ in }
        )
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ONE - Spell") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        NHMenuSheet(
            context: NHMenuContext(
                prompt: "Cast which spell?",
                pickMode: .one,
                items: [
                    .item("force bolt (1)", selector: "a"),
                    .item("magic missile (2)", selector: "b"),
                    .item("cone of cold (4)", selector: "c"),
                    .item("fireball (4)", selector: "d"),
                ],
                subtitle: "12 MP available",
                icon: "wand.and.stars"
            ),
            onSelect: { selections in
                print("Selected: \(selections)")
            }
        )
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ANY - Pickup") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        NHMenuSheet(
            context: NHMenuContext(
                prompt: "Pick up what?",
                pickMode: .any,
                items: [
                    NHMenuItem(selector: "a", text: "5 gold pieces", count: 5),
                    NHMenuItem(selector: "b", text: "a rusty dagger"),
                    NHMenuItem(selector: "c", text: "3 food rations", count: 3),
                    NHMenuItem(selector: "d", text: "a scroll of identify"),
                ],
                subtitle: "Carrying 45/52 lbs",
                icon: "arrow.down.circle.fill"
            ),
            onSelect: { selections in
                print("Selected: \(selections)")
            }
        )
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("Empty State") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        NHMenuSheet(
            context: NHMenuContext(
                prompt: "Nothing here",
                pickMode: .none,
                items: [],
                icon: "tray"
            ),
            onSelect: { _ in }
        )
    }
    .previewInterfaceOrientation(.landscapeLeft)
}
