import SwiftUI

// MARK: - Menu Header
/// Compact inline header component for NetHack menus
/// Redesigned to match ItemSelectionSheet style - no drag handle, smaller footprint
struct MenuHeader: View {
    let prompt: String
    let pickMode: NHPickMode
    let subtitle: String?
    let icon: String?
    let itemCount: Int
    let onClose: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone
    private let accentColor = Color.nethackAccent

    // MARK: - Init

    init(
        prompt: String,
        pickMode: NHPickMode,
        subtitle: String? = nil,
        icon: String? = nil,
        itemCount: Int = 0,
        onClose: (() -> Void)? = nil
    ) {
        self.prompt = prompt
        self.pickMode = pickMode
        self.subtitle = subtitle
        self.icon = icon
        self.itemCount = itemCount
        self.onClose = onClose
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: isPhone ? 6 : 10) {
                // Icon in colored circle
                if let iconName = icon {
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
                Text(prompt)
                    .font(.system(size: isPhone ? 13 : 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // Item count pill
                if itemCount > 0 {
                    Text("\(itemCount)")
                        .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(0.3))
                        )
                }

                // Close button (PICK_NONE and PICK_ONE only)
                if pickMode != .any, let close = onClose {
                    closeButton(action: close)
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 6 : 8)

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }

    // MARK: - Close Button

    @State private var isClosePressed = false

    private func closeButton(action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.tap()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isClosePressed ? 0.2 : 0.1))
                )
                .scaleEffect(isClosePressed ? AnimationConstants.pressScale : 1.0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isClosePressed = true }
                .onEnded { _ in isClosePressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isClosePressed)
        .accessibilityLabel("Close")
    }
}

// MARK: - Preview

#Preview("PICK_NONE with close") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            MenuHeader(
                prompt: "Discoveries",
                pickMode: .none,
                icon: "sparkles",
                itemCount: 12,
                onClose: {}
            )
            Spacer()
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ONE") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            MenuHeader(
                prompt: "Cast which spell?",
                pickMode: .one,
                icon: "wand.and.stars",
                itemCount: 4,
                onClose: {}
            )
            Spacer()
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("PICK_ANY") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            MenuHeader(
                prompt: "Pick up what?",
                pickMode: .any,
                icon: "arrow.down.circle.fill",
                itemCount: 7
            )
            Spacer()
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}
