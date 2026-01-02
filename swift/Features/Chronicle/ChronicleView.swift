import SwiftUI

// MARK: - ChronicleView
/// Hero's Chronicle - Epic journey log showing major game events
/// Glass-morphic design with visual hierarchy based on event rarity
struct ChronicleView: View {
    let entries: [ChronicleEntry]
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    // MARK: - Colors by Rarity

    private let goldColor = Color(hue: 0.12, saturation: 0.7, brightness: 0.85)  // Gold for legendary
    private let accentColor = Color.nethackAccent  // Orange for epic

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismissChronicle() }

            // Main sheet
            VStack(spacing: 0) {
                chronicleHeader

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)

                if entries.isEmpty {
                    emptyState
                } else {
                    eventTimeline
                }
            }
            .frame(maxWidth: isPhone ? 380 : 500)
            .frame(maxHeight: isPhone ? 450 : 550)
            .background(sheetBackground)
            .clipShape(RoundedRectangle(cornerRadius: isPhone ? 16 : 20, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 8)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .opacity(hasAppeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.15)) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hasAppeared)
    }

    // MARK: - Header

    private var chronicleHeader: some View {
        HStack(spacing: isPhone ? 8 : 12) {
            // Icon
            Image(systemName: "book.pages.fill")
                .font(.system(size: isPhone ? 16 : 20, weight: .semibold))
                .foregroundColor(goldColor)
                .frame(width: isPhone ? 32 : 40, height: isPhone ? 32 : 40)
                .background(
                    Circle()
                        .fill(goldColor.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Chronicle")
                    .font(.system(size: isPhone ? 16 : 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Your heroic journey")
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Event count
            if !entries.isEmpty {
                Text("\(entries.count)")
                    .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.3))
                    )
            }

            // Close button
            Button {
                dismissChronicle()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: isPhone ? 28 : 32, height: isPhone ? 28 : 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, isPhone ? 16 : 20)
        .padding(.vertical, isPhone ? 12 : 16)
    }

    // MARK: - Event Timeline

    private var eventTimeline: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: isPhone ? 8 : 12) {
                // Reverse chronological - newest first
                ForEach(entries.reversed()) { entry in
                    ChronicleEventCard(entry: entry, isPhone: isPhone)
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 8 : 12)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: isPhone ? 40 : 48))
                .foregroundColor(.white.opacity(0.2))

            Text("Your Chronicle Awaits")
                .font(.system(size: isPhone ? 16 : 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            Text("Major events like wishes, artifacts,\nand legendary achievements will appear here.")
                .font(.system(size: isPhone ? 12 : 14))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Background

    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: isPhone ? 16 : 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 16 : 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                goldColor.opacity(0.3),
                                Color.white.opacity(0.1),
                                goldColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Actions

    private func dismissChronicle() {
        HapticManager.shared.tap()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)) {
            hasAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - Event Card

private struct ChronicleEventCard: View {
    let entry: ChronicleEntry
    let isPhone: Bool

    private var cardColor: Color {
        switch entry.rarity {
        case .legendary: return Color(hue: 0.12, saturation: 0.7, brightness: 0.85)  // Gold
        case .epic: return Color.nethackAccent  // Orange
        case .major: return Color.white.opacity(0.6)
        case .minor: return Color.white.opacity(0.4)
        }
    }

    private var iconSize: CGFloat {
        switch entry.rarity {
        case .legendary: return isPhone ? 22 : 26
        case .epic: return isPhone ? 20 : 24
        case .major: return isPhone ? 18 : 22
        case .minor: return isPhone ? 16 : 20
        }
    }

    private var titleWeight: Font.Weight {
        switch entry.rarity {
        case .legendary: return .bold
        case .epic: return .semibold
        case .major: return .medium
        case .minor: return .regular
        }
    }

    var body: some View {
        HStack(spacing: isPhone ? 10 : 14) {
            // Event Icon
            Image(systemName: entry.eventType.icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(cardColor)
                .frame(width: isPhone ? 36 : 44, height: isPhone ? 36 : 44)
                .background(
                    Circle()
                        .fill(cardColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                // Top row: Turn + Category
                HStack(spacing: 6) {
                    Text("T:\(entry.turn)")
                        .font(.system(size: isPhone ? 10 : 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    categoryPill
                }

                // Event text
                Text(entry.text)
                    .font(.system(size: isPhone ? 13 : 15, weight: titleWeight))
                    .foregroundColor(.white.opacity(entry.rarity == .minor ? 0.7 : 0.9))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(isPhone ? 10 : 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isPhone ? 10 : 12))
    }

    private var categoryPill: some View {
        HStack(spacing: 3) {
            Image(systemName: entry.eventType.icon)
                .font(.system(size: isPhone ? 8 : 9))
            Text(entry.eventType.label)
                .font(.system(size: isPhone ? 9 : 10, weight: .medium))
        }
        .foregroundColor(cardColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(cardColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .strokeBorder(cardColor.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch entry.rarity {
        case .legendary:
            // Gold glow for legendary
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .fill(
                            LinearGradient(
                                colors: [cardColor.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [cardColor.opacity(0.5), cardColor.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )

        case .epic:
            // Accent border for epic
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .fill(cardColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .strokeBorder(cardColor.opacity(0.35), lineWidth: 1)
                )

        case .major:
            // Subtle border for major
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

        case .minor:
            // Minimal for minor
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.03))
        }
    }
}

// MARK: - Preview

#Preview("Chronicle - With Events") {
    ZStack {
        Color.black.ignoresSafeArea()

        ChronicleView(
            entries: [
                ChronicleEntry(turn: 1234, flags: 0x0001, text: "wished for \"blessed magic marker\""),
                ChronicleEntry(turn: 892, flags: 0x0040, text: "found Grayswandir"),
                ChronicleEntry(turn: 654, flags: 0x0080, text: "genocided h (mind flayers)"),
                ChronicleEntry(turn: 423, flags: 0x0008, text: "received Mjollnir from Tyr"),
                ChronicleEntry(turn: 156, flags: 0x0004, text: "killed Medusa"),
                ChronicleEntry(turn: 42, flags: 0x1000, text: "entered the Gnomish Mines")
            ],
            onDismiss: {}
        )
    }
}

#Preview("Chronicle - Empty") {
    ZStack {
        Color.black.ignoresSafeArea()
        ChronicleView(entries: [], onDismiss: {})
    }
}
