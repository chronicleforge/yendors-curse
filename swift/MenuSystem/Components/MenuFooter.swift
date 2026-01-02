import SwiftUI

// MARK: - Menu Footer
/// Compact footer component for PICK_ANY menus
/// Redesigned to match ItemSelectionSheet style
struct MenuFooter: View {
    let selectedCount: Int
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone
    private let accentColor = Color.nethackAccent

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)

            HStack(spacing: isPhone ? 8 : 12) {
                // Selection count
                Text(selectionText)
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white.opacity(0.6))
                    .accessibilityLabel("\(selectedCount) items selected")

                Spacer()

                // Cancel button
                Button {
                    HapticManager.shared.tap()
                    onCancel()
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
                .accessibilityLabel("Cancel selection")

                // Done button
                Button {
                    HapticManager.shared.success()
                    onConfirm()
                } label: {
                    Text("Done")
                        .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                        .foregroundColor(selectedCount == 0 ? .white.opacity(0.4) : .white)
                        .padding(.horizontal, isPhone ? 16 : 20)
                        .padding(.vertical, isPhone ? 6 : 8)
                        .background(
                            Capsule()
                                .fill(selectedCount == 0 ? Color.white.opacity(0.1) : accentColor)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
                .accessibilityLabel("Confirm selection")
                .accessibilityHint(selectedCount == 0 ? "Select at least one item" : "")
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 8 : 10)
        }
    }

    // MARK: - Computed

    private var selectionText: String {
        switch selectedCount {
        case 0: return "None selected"
        case 1: return "1 selected"
        default: return "\(selectedCount) selected"
        }
    }
}

// MARK: - Preview

#Preview("No selection") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            MenuFooter(
                selectedCount: 0,
                onCancel: {},
                onConfirm: {}
            )
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("Single selection") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            MenuFooter(
                selectedCount: 1,
                onCancel: {},
                onConfirm: {}
            )
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}

#Preview("Multiple selections") {
    ZStack {
        LinearGradient(
            colors: [Color(white: 0.1), Color(white: 0.05)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack {
            Spacer()
            MenuFooter(
                selectedCount: 5,
                onCancel: {},
                onConfirm: {}
            )
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .previewInterfaceOrientation(.landscapeLeft)
}
