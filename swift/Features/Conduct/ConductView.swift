import SwiftUI

// MARK: - ConductView
/// Voluntary Challenges display - shows maintained and broken conducts
/// Glass-morphic design matching ChronicleView
struct ConductView: View {
    let conductData: ConductData
    let onDismiss: () -> Void

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    // Colors
    private let maintainedColor = Color.green
    private let brokenColor = Color.gray
    private let permanentColor = Color.blue
    private let accentColor = Color.nethackAccent

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismissView() }

            // Main sheet
            VStack(spacing: 0) {
                conductHeader

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 0.5)

                conductList
            }
            .frame(maxWidth: isPhone ? 380 : 500)
            .frame(maxHeight: isPhone ? 500 : 600)
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

    private var conductHeader: some View {
        HStack(spacing: isPhone ? 8 : 12) {
            // Icon
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: isPhone ? 16 : 20, weight: .semibold))
                .foregroundColor(maintainedColor)
                .frame(width: isPhone ? 32 : 40, height: isPhone ? 32 : 40)
                .background(
                    Circle()
                        .fill(maintainedColor.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Conduct")
                    .font(.system(size: isPhone ? 16 : 20, weight: .bold))
                    .foregroundColor(.white)

                Text("Voluntary challenges")
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Stats summary
            let entries = conductData.getConductEntries()
            let maintained = entries.filter { $0.status == .maintained || $0.status == .permanent }.count

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(maintainedColor)
                Text("\(maintained)")
                    .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .rounded))
                    .foregroundColor(maintainedColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(maintainedColor.opacity(0.2))
            )

            // Close button
            Button {
                dismissView()
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

    // MARK: - Conduct List

    private var conductList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: isPhone ? 6 : 8) {
                ForEach(conductData.getConductEntries()) { entry in
                    ConductEntryCard(entry: entry, isPhone: isPhone)
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 8 : 12)
        }
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
                                maintainedColor.opacity(0.3),
                                Color.white.opacity(0.1),
                                maintainedColor.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Actions

    private func dismissView() {
        HapticManager.shared.tap()
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0)) {
            hasAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss()
        }
    }
}

// MARK: - Conduct Entry Card

private struct ConductEntryCard: View {
    let entry: ConductEntry
    let isPhone: Bool

    private var statusColor: Color {
        switch entry.status {
        case .maintained: return .green
        case .broken: return .gray
        case .permanent: return .blue
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .maintained: return "checkmark.circle.fill"
        case .broken: return "xmark.circle"
        case .permanent: return "star.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: isPhone ? 10 : 14) {
            // Conduct Icon
            Image(systemName: entry.icon)
                .font(.system(size: isPhone ? 18 : 22, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: isPhone ? 36 : 44, height: isPhone ? 36 : 44)
                .background(
                    Circle()
                        .fill(statusColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                // Name
                Text(entry.name)
                    .font(.system(size: isPhone ? 14 : 16, weight: entry.status == .broken ? .regular : .semibold))
                    .foregroundColor(entry.status == .broken ? .white.opacity(0.5) : .white.opacity(0.9))

                // Description
                Text(entry.description)
                    .font(.system(size: isPhone ? 11 : 13))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            // Status indicator
            Image(systemName: statusIcon)
                .font(.system(size: isPhone ? 16 : 18))
                .foregroundColor(statusColor)
        }
        .padding(isPhone ? 10 : 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isPhone ? 10 : 12))
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch entry.status {
        case .maintained:
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .fill(statusColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.5)
                )

        case .permanent:
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .fill(statusColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                        .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
                )

        case .broken:
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12)
                .fill(Color.white.opacity(0.02))
        }
    }
}

// MARK: - Preview

#Preview("Conduct - Mixed") {
    ZStack {
        Color.black.ignoresSafeArea()

        ConductView(
            conductData: ConductData(
                unvegetarian: 5,
                unvegan: 10,
                food: 15,
                gnostic: 0,
                weaphit: 0,
                killer: 42,
                literate: 3,
                polypiles: 0,
                polyselfs: 0,
                wishes: 1,
                wisharti: 1,
                sokocheat: 0,
                pets: 1,
                blind: 0,
                deaf: 0,
                nudist: 1,
                pauper: 0,
                sokoban_entered: 1,
                genocides: 0,
                turns: 5000
            ),
            onDismiss: {}
        )
    }
}
