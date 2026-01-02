import SwiftUI

// MARK: - Text Input Sheet

/// Generic text input sheet with suggestions
/// Used for engrave custom, name, genocide, polymorph
struct TextInputSheet: View {
    let context: TextInputContext
    let onDismiss: () -> Void

    @State private var inputText: String = ""
    @State private var searchText: String = ""
    @State private var isCustomExpanded: Bool = false
    @State private var isSubmitting: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let isPhone = ScalingEnvironment.isPhone

    // MARK: - Layout Constants

    private var sheetWidth: CGFloat {
        isPhone ? 340 : 420
    }

    private var pillHeight: CGFloat {
        isPhone ? 44 : 48
    }

    private var customButtonHeight: CGFloat {
        isPhone ? 50 : 56
    }

    private var maxScrollHeight: CGFloat {
        isPhone ? 240 : 320
    }

    // MARK: - Filtered Suggestions

    private var filteredKilled: [DiscoveredMonster] {
        guard !searchText.isEmpty else { return context.killedMonsters }
        let search = searchText.lowercased()
        return context.killedMonsters.filter { $0.name.lowercased().contains(search) }
    }

    private var filteredSeen: [DiscoveredMonster] {
        guard !searchText.isEmpty else { return context.seenMonsters }
        let search = searchText.lowercased()
        return context.seenMonsters.filter { $0.name.lowercased().contains(search) }
    }

    private var filteredStatic: [String] {
        guard !searchText.isEmpty else { return context.staticSuggestions }
        let search = searchText.lowercased()
        return context.staticSuggestions.filter { $0.lowercased().contains(search) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmer background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSheet()
                }

            // Main sheet
            VStack(spacing: 0) {
                // Header
                sheetHeader

                Divider()
                    .background(context.color.opacity(0.3))

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Search field at TOP (if enabled) for quick filtering
                        if context.showSearch {
                            searchField
                        }

                        // Static suggestions (for engrave/wish)
                        if !filteredStatic.isEmpty {
                            staticSuggestionsSection
                        }

                        // Killed monsters section
                        if !filteredKilled.isEmpty {
                            monsterSection(
                                title: "Killed (\(context.killedMonsters.count))",
                                monsters: filteredKilled,
                                icon: "checkmark.circle.fill",
                                iconColor: .red
                            )
                        }

                        // Seen monsters section
                        if !filteredSeen.isEmpty {
                            monsterSection(
                                title: "Seen (\(context.seenMonsters.count))",
                                monsters: filteredSeen,
                                icon: "eye.fill",
                                iconColor: .gray
                            )
                        }

                        // Divider with OR
                        orDivider

                        // Custom input section (manual text entry)
                        customInputSection
                    }
                    .padding()
                }
                .frame(maxHeight: maxScrollHeight)
            }
            .frame(width: sheetWidth)
            .background(sheetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isCustomExpanded)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: context.icon)
                .font(.title2)
                .foregroundColor(context.color)

            Text(context.prompt)
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                dismissSheet()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Static Suggestions

    private var staticSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Options")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !searchText.isEmpty {
                    Text("\(filteredStatic.count) of \(context.staticSuggestions.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(filteredStatic, id: \.self) { suggestion in
                    SuggestionPill(
                        text: suggestion,
                        height: pillHeight,
                        color: context.color
                    ) {
                        submitText(suggestion)
                    }
                }
            }
        }
    }

    // MARK: - Monster Section

    private func monsterSection(
        title: String,
        monsters: [DiscoveredMonster],
        icon: String,
        iconColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(monsters.prefix(20)) { monster in
                    SuggestionPill(
                        text: monster.displayName,
                        subtitle: monster.subtitle,
                        height: pillHeight,
                        color: context.color
                    ) {
                        submitText(monster.name)
                    }
                }
            }

            // Show count if more than 20
            if monsters.count > 20 {
                Text("+ \(monsters.count - 20) more (use search)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Search Field (also serves as custom input for wish)

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        // Allow submitting search text directly (for custom wishes)
                        if !searchText.isEmpty {
                            submitText(searchText)
                        }
                    }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(10)

            // Direct submit button when text is entered
            if !searchText.isEmpty {
                Button {
                    submitText(searchText)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(context.color)
                }
                .buttonStyle(.plain)
                .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: searchText.isEmpty)
    }

    private var searchPlaceholder: String {
        context.prompt.contains("wish") ? "Search or type custom wish..." : "Search..."
    }

    // MARK: - OR Divider

    private var orDivider: some View {
        HStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)

            Text("OR")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Custom Input Section

    private var customInputSection: some View {
        VStack(spacing: 12) {
            if isCustomExpanded {
                // Expanded: Text field with submit button
                HStack(spacing: 8) {
                    TextField(context.placeholder, text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .focused($isTextFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            submitCustomText()
                        }

                    Button {
                        submitCustomText()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(inputText.isEmpty ? .secondary : context.color)
                    }
                    .disabled(inputText.isEmpty)
                    .buttonStyle(.plain)
                }
                .frame(height: customButtonHeight)
            } else {
                // Collapsed: Button to expand
                Button {
                    withAnimation {
                        isCustomExpanded = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTextFieldFocused = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundColor(context.color)

                        Text("Custom...")
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(height: customButtonHeight)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Background

    private var sheetBackground: some View {
        ZStack {
            // Glass effect
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)

            // Gradient border
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            context.color.opacity(0.3),
                            context.color.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - Actions

    private func submitText(_ text: String) {
        guard !isSubmitting else { return }
        isSubmitting = true

        HapticManager.shared.buttonPress()
        context.onSubmit(text)
        onDismiss()
    }

    private func submitCustomText() {
        guard !inputText.isEmpty else { return }
        submitText(inputText)
    }

    private func dismissSheet() {
        HapticManager.shared.tap()
        onDismiss()
    }
}

// MARK: - Suggestion Pill

struct SuggestionPill: View {
    let text: String
    var subtitle: String? = nil
    let height: CGFloat
    let color: Color
    let action: () -> Void

    @State private var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    TextInputSheet(
        context: .genocide { text in
            print("Genocide: \(text)")
        },
        onDismiss: {}
    )
}
