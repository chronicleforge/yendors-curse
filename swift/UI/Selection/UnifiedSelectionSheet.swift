import SwiftUI

// MARK: - Selection Section Model

/// A generic section of selectable items
/// Used by UnifiedSelectionSheet to display grouped content
struct SelectionSection: Identifiable {
    let id = UUID()
    let header: String?
    let headerIcon: String?
    let headerColor: Color
    let items: [SelectionItem]
    
    init(
        header: String? = nil,
        headerIcon: String? = nil,
        headerColor: Color = .white,
        items: [SelectionItem]
    ) {
        self.header = header
        self.headerIcon = headerIcon
        self.headerColor = headerColor
        self.items = items
    }
}

// MARK: - Selection Item Model

/// A selectable item that can represent different source types
/// Unified model for inventory items, ground items, and text suggestions
struct SelectionItem: Identifiable {
    let id: String
    let displayText: String
    let subtitle: String?
    let badge: Badge?
    let icon: Icon?
    let bucIndicator: BUCIndicator?
    let quantity: Int?
    let accentColor: Color
    let onSelect: () -> Void
    
    /// Badge displayed on the left (inventory letter, ground arrow, etc.)
    enum Badge {
        case letter(Character)      // Inventory letter (a-z, A-Z)
        case groundArrow            // Arrow down for ground items
        case none
        
        var isLetter: Bool {
            if case .letter = self { return true }
            return false
        }
    }
    
    /// Icon displayed after badge (category icon, emoji, etc.)
    enum Icon {
        case sfSymbol(String, Color)
        case emoji(String)
        case none
    }
    
    /// BUC status indicator
    enum BUCIndicator {
        case blessed
        case cursed
        case uncursed
        case none
    }
    
    // MARK: - Factory Methods
    
    /// Create from NetHackItem (inventory)
    static func fromInventoryItem(
        _ item: NetHackItem,
        accentColor: Color,
        onSelect: @escaping () -> Void
    ) -> SelectionItem {
        let bucIndicator: BUCIndicator = {
            guard item.bucKnown else { return .none }
            switch item.bucStatus {
            case .blessed: return .blessed
            case .cursed: return .cursed
            case .uncursed: return .uncursed
            case .unknown: return .none
            }
        }()
        
        return SelectionItem(
            id: item.id,
            displayText: item.cleanName,
            subtitle: nil,
            badge: .letter(item.invlet),
            icon: .sfSymbol(item.category.icon, item.category.color),
            bucIndicator: bucIndicator,
            quantity: item.quantity > 1 ? item.quantity : nil,
            accentColor: accentColor,
            onSelect: onSelect
        )
    }
    
    /// Create from GameObjectInfo (ground item)
    static func fromGroundItem(
        _ item: GameObjectInfo,
        accentColor: Color,
        onSelect: @escaping () -> Void
    ) -> SelectionItem {
        let bucIndicator: BUCIndicator = {
            guard item.bucKnown else { return .none }
            if item.blessed { return .blessed }
            if item.cursed { return .cursed }
            return .uncursed
        }()
        
        return SelectionItem(
            id: item.id.uuidString,
            displayText: item.cleanName,
            subtitle: nil,
            badge: .groundArrow,
            icon: .emoji(item.icon),
            bucIndicator: bucIndicator,
            quantity: item.quantity > 1 ? item.quantity : nil,
            accentColor: accentColor,
            onSelect: onSelect
        )
    }
    
    /// Create from text suggestion (monster, wish item, etc.)
    static func fromTextSuggestion(
        _ text: String,
        subtitle: String? = nil,
        accentColor: Color,
        onSelect: @escaping () -> Void
    ) -> SelectionItem {
        SelectionItem(
            id: text,
            displayText: text,
            subtitle: subtitle,
            badge: .none,
            icon: .none,
            bucIndicator: .none,
            quantity: nil,
            accentColor: accentColor,
            onSelect: onSelect
        )
    }
    
    /// Create from DiscoveredMonster
    static func fromMonster(
        _ monster: DiscoveredMonster,
        accentColor: Color,
        onSelect: @escaping () -> Void
    ) -> SelectionItem {
        SelectionItem(
            id: String(monster.id),
            displayText: monster.displayName,
            subtitle: monster.subtitle,
            badge: .none,
            icon: .none,
            bucIndicator: .none,
            quantity: nil,
            accentColor: accentColor,
            onSelect: onSelect
        )
    }
}

// MARK: - Selection Configuration

/// Configuration for UnifiedSelectionSheet
/// Replaces both TextInputContext and ItemSelectionContext
struct SelectionConfiguration {
    let prompt: String
    let icon: String
    let color: Color
    let sections: [SelectionSection]
    let showSearch: Bool
    let searchPlaceholder: String
    let showCustomInput: Bool
    let customInputPlaceholder: String
    let emptyMessage: String
    let onCustomSubmit: ((String) -> Void)?
    
    init(
        prompt: String,
        icon: String,
        color: Color,
        sections: [SelectionSection],
        showSearch: Bool = false,
        searchPlaceholder: String = "Search...",
        showCustomInput: Bool = false,
        customInputPlaceholder: String = "Enter custom...",
        emptyMessage: String = "No items available.",
        onCustomSubmit: ((String) -> Void)? = nil
    ) {
        self.prompt = prompt
        self.icon = icon
        self.color = color
        self.sections = sections
        self.showSearch = showSearch
        self.searchPlaceholder = searchPlaceholder
        self.showCustomInput = showCustomInput
        self.customInputPlaceholder = customInputPlaceholder
        self.emptyMessage = emptyMessage
        self.onCustomSubmit = onCustomSubmit
    }
    
    /// Total number of items across all sections
    var totalItemCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }
    
    /// Check if there are any items to display
    var hasItems: Bool {
        totalItemCount > 0
    }
}

// MARK: - UnifiedSelectionSheet

/// Premium glass-morphic selection sheet for both item and text selection
/// Consolidates ItemSelectionSheet and TextInputSheet into a single component
///
/// Design Philosophy:
/// - **Compact Vertical Grid**: 2-column layout for efficient scanning
/// - **Touch-First**: 44pt minimum touch targets, thumb-reachable
/// - **Glass-morphic**: Consistent with app design system
/// - **Accessibility**: Respects Reduce Motion (SWIFTUI-A-009)
///
/// Ref: SWIFTUI-L-001 (layout), SWIFTUI-A-001 (animation)
struct UnifiedSelectionSheet: View {
    let config: SelectionConfiguration
    let onDismiss: () -> Void
    
    @State private var searchText: String = ""
    @State private var customInputText: String = ""
    @State private var isCustomExpanded: Bool = false
    @State private var hasAppeared: Bool = false
    @FocusState private var isTextFieldFocused: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private let isPhone = ScalingEnvironment.isPhone
    
    // MARK: - Layout Constants
    
    private var sheetWidth: CGFloat { isPhone ? 340 : 420 }
    private var pillHeight: CGFloat { isPhone ? 44 : 48 }
    private var maxScrollHeight: CGFloat { isPhone ? 340 : 420 }
    private var customButtonHeight: CGFloat { isPhone ? 50 : 56 }
    private var cornerRadius: CGFloat { isPhone ? 12 : 16 }
    
    // MARK: - Filtered Sections
    
    private var filteredSections: [SelectionSection] {
        guard !searchText.isEmpty else { return config.sections }
        
        let search = searchText.lowercased()
        return config.sections.compactMap { section in
            let filteredItems = section.items.filter { item in
                item.displayText.lowercased().contains(search) ||
                (item.subtitle?.lowercased().contains(search) ?? false)
            }
            guard !filteredItems.isEmpty else { return nil }
            return SelectionSection(
                header: section.header,
                headerIcon: section.headerIcon,
                headerColor: section.headerColor,
                items: filteredItems
            )
        }
    }
    
    private var hasAnyItems: Bool {
        !filteredSections.isEmpty || config.showCustomInput
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Dimmer background (for modal presentation)
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSheet()
                }
            
            // Main sheet
            VStack(spacing: 0) {
                sheetHeader
                
                // Thin separator
                Rectangle()
                    .fill(config.color.opacity(0.2))
                    .frame(height: 0.5)
                
                // Content
                if hasAnyItems {
                    mainContent
                } else {
                    emptyState
                }
            }
            .frame(width: sheetWidth)
            .background(sheetBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: -4)
            .transition(sheetTransition)
            .animation(reduceMotion ? nil : AnimationConstants.sheetAppear, value: hasAppeared)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : AnimationConstants.sheetAppear) {
                hasAppeared = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCustomExpanded)
        .sensoryFeedback(.impact(weight: .light), trigger: hasAppeared)
    }
    
    // MARK: - Header
    
    private var sheetHeader: some View {
        HStack(spacing: isPhone ? 6 : 10) {
            // Context icon
            Image(systemName: config.icon)
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(config.color)
                .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                .background(
                    Circle()
                        .fill(config.color.opacity(0.2))
                )
            
            // Prompt
            Text(config.prompt)
                .font(.system(size: isPhone ? 13 : 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer(minLength: 8)
            
            // Item count pill
            if config.hasItems {
                let filteredCount = filteredSections.reduce(0) { $0 + $1.items.count }
                Text("\(filteredCount)")
                    .font(.system(size: isPhone ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(config.color.opacity(0.3))
                    )
                    .animation(reduceMotion ? nil : AnimationConstants.statusUpdate, value: filteredCount)
            }
            
            // Close button
            UnifiedCloseButton(reduceMotion: reduceMotion) {
                dismissSheet()
            }
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .padding(.vertical, isPhone ? 6 : 8)
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: isPhone ? 12 : 16) {
                // Search field (optional)
                if config.showSearch {
                    searchField
                }
                
                // Sections
                ForEach(filteredSections) { section in
                    sectionView(section)
                }
                
                // Custom input section (optional)
                if config.showCustomInput {
                    if !filteredSections.isEmpty {
                        orDivider
                    }
                    customInputSection
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, isPhone ? 6 : 10)
        }
        .frame(maxHeight: maxScrollHeight)
    }
    
    // MARK: - Section View
    
    @ViewBuilder
    private func sectionView(_ section: SelectionSection) -> some View {
        VStack(alignment: .leading, spacing: isPhone ? 4 : 6) {
            // Section header
            if let header = section.header {
                HStack(spacing: 4) {
                    if let icon = section.headerIcon {
                        Image(systemName: icon)
                            .font(.system(size: isPhone ? 10 : 12, weight: .medium))
                            .foregroundColor(section.headerColor.opacity(0.7))
                    }
                    Text(header)
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))  // Increased from 0.5 for better scannability
                        .textCase(.uppercase)
                    
                    if !searchText.isEmpty {
                        Text("(\(section.items.count))")
                            .font(.system(size: isPhone ? 9 : 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 2)
            }
            
            // Items grid (single column for full item name visibility)
            LazyVGrid(
                columns: [GridItem(.flexible())],
                spacing: isPhone ? 4 : 6
            ) {
                ForEach(Array(section.items.prefix(40).enumerated()), id: \.element.id) { index, item in
                    UnifiedPill(
                        item: item,
                        height: pillHeight,
                        index: index,
                        reduceMotion: reduceMotion
                    )
                }
            }
            
            // Show count if more than 40 items
            if section.items.count > 40 {
                Text("+ \(section.items.count - 40) more (use search)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
    
    // MARK: - Search Field (also serves as direct input for wishes)

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField(config.searchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        // Allow submitting search text directly (for custom wishes)
                        if !searchText.isEmpty, let onSubmit = config.onCustomSubmit {
                            HapticManager.shared.buttonPress()
                            onSubmit(searchText)
                            onDismiss()
                        }
                    }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .cornerRadius(10)

            // Direct submit button when text is entered
            if !searchText.isEmpty, config.onCustomSubmit != nil {
                Button {
                    if let onSubmit = config.onCustomSubmit {
                        HapticManager.shared.buttonPress()
                        onSubmit(searchText)
                        onDismiss()
                    }
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(config.color)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: searchText.isEmpty)
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
                    TextField(config.customInputPlaceholder, text: $customInputText)
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
                            .foregroundColor(customInputText.isEmpty ? .secondary : config.color)
                    }
                    .disabled(customInputText.isEmpty)
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
                            .foregroundColor(config.color)
                        
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
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: isPhone ? 18 : 22))
                    .foregroundColor(.white.opacity(0.25))
                    .emptyStateIconAnimation()
                
                Text(config.emptyMessage)
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isPhone ? 16 : 24)
        .emptyStateEntrance(isVisible: hasAppeared, reduceMotion: reduceMotion)
    }
    
    // MARK: - Sheet Background
    
    private var sheetBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                config.color.opacity(0.25),
                                Color.white.opacity(0.08),
                                config.color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
    
    private var sheetTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : AnimationConstants.sheetAppearTransition
    }
    
    // MARK: - Actions
    
    private func submitCustomText() {
        guard !customInputText.isEmpty else { return }
        HapticManager.shared.buttonPress()
        config.onCustomSubmit?(customInputText)
        onDismiss()
    }
    
    private func dismissSheet() {
        HapticManager.shared.tap()
        onDismiss()
    }
}

// MARK: - UnifiedPill

/// Universal pill component for selection sheets
/// Handles inventory items, ground items, and text suggestions
private struct UnifiedPill: View {
    let item: SelectionItem
    let height: CGFloat
    let index: Int
    let reduceMotion: Bool
    
    @State private var isPressed = false
    @State private var isConfirming = false
    @State private var hasAppeared = false
    @State private var showDetails = false

    private let isPhone = ScalingEnvironment.isPhone
    
    private var entranceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        guard AnimationConstants.shouldStaggerItem(at: index) else {
            return AnimationConstants.itemCardBaseEntrance
        }
        return AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
    }
    
    var body: some View {
        Button {
            guard !isConfirming else { return }
            isConfirming = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                item.onSelect()
            }
        } label: {
            HStack(spacing: isPhone ? 6 : 8) {
                // Badge (letter or ground arrow)
                badgeView
                
                // Icon (SF Symbol or emoji)
                iconView
                
                // BUC indicator
                bucIndicatorView
                
                // Item text
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayText)
                        .font(.system(size: isPhone ? 11 : 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer(minLength: 4)
                
                // Quantity badge
                if let quantity = item.quantity {
                    Text("\u{00D7}\(quantity)")  // multiplication sign
                        .font(.system(size: isPhone ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, isPhone ? 5 : 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal, isPhone ? 8 : 10)
            .frame(height: height)
            .background(pillBackground)
            .scaleEffect(
                isConfirming
                    ? AnimationConstants.selectionConfirmationScale
                    : (isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            )
            .opacity(hasAppeared ? 1.0 : 0.0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isConfirming else { return }
                    isPressed = true
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.itemCardPress, value: isPressed)
        .animation(reduceMotion ? nil : AnimationConstants.selectionConfirmation, value: isConfirming)
        .onAppear {
            withAnimation(entranceAnimation) {
                hasAppeared = true
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isConfirming)
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticManager.shared.tap()
            showDetails = true
        }
        .popover(isPresented: $showDetails, arrowEdge: .leading) {
            SelectionItemDetailPopover(item: item)
        }
    }

    // MARK: - Badge View

    @ViewBuilder
    private var badgeView: some View {
        if let badge = item.badge {
            switch badge {
            case .letter(let char):
                Text(String(char))
                    .font(.system(size: isPhone ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.accentColor)
                    )

            case .groundArrow:
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: isPhone ? 24 : 28, height: isPhone ? 24 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.accentColor)
                    )

            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Icon View

    @ViewBuilder
    private var iconView: some View {
        if let icon = item.icon {
            switch icon {
            case .sfSymbol(let name, let color):
                Image(systemName: name)
                    .font(.system(size: isPhone ? 12 : 14))
                    .foregroundColor(color.opacity(0.8))
                    .frame(width: isPhone ? 16 : 20)

            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: isPhone ? 14 : 16))
                    .frame(width: isPhone ? 16 : 20)

            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - BUC Indicator View

    @ViewBuilder
    private var bucIndicatorView: some View {
        if let bucIndicator = item.bucIndicator {
            switch bucIndicator {
            case .blessed:
                // Larger sparkles for better visibility (UX review recommendation)
                Image(systemName: "sparkles")
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(.green)
                    .shadow(color: .green.opacity(0.4), radius: 2)

            case .cursed:
                // Prominent warning for dangerous items
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.4), radius: 2)

            case .uncursed:
                // Subtle neutral indicator (not positive like checkmark)
                Circle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: isPhone ? 6 : 8, height: isPhone ? 6 : 8)

            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Pill Background

    private var pillBackground: some View {
        let fillOpacity: Double = {
            if isConfirming { return 0.2 }
            if isPressed { return 0.12 }
            return 0.05
        }()

        let borderColor: Color = isConfirming
            ? item.accentColor.opacity(0.6)
            : pillBorderColor

        let isCursed: Bool = {
            guard let bucIndicator = item.bucIndicator else { return false }
            return bucIndicator == .cursed
        }()

        let borderWidth: CGFloat = {
            if isConfirming { return 2 }
            if isCursed { return 1.5 }
            return 0.5
        }()

        return RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
            .fill(Color.white.opacity(fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: isPhone ? 8 : 10)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
    }

    private var pillBorderColor: Color {
        guard let bucIndicator = item.bucIndicator else { return .white.opacity(0.1) }
        switch bucIndicator {
        case .blessed: return .green.opacity(0.4)
        case .cursed: return .red.opacity(0.5)
        case .uncursed, .none: return .white.opacity(0.1)
        }
    }
}

// MARK: - Selection Item Detail Popover

/// Popover showing full item details on long press
private struct SelectionItemDetailPopover: View {
    let item: SelectionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Item icon and full name
            HStack(spacing: 10) {
                iconForPopover

                Text(item.displayText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // BUC status
            if let buc = item.bucIndicator, buc != .none {
                detailRow(
                    icon: bucIcon(buc),
                    iconColor: bucColor(buc),
                    label: bucLabel(buc)
                )
            }

            // Quantity
            if let qty = item.quantity, qty > 1 {
                detailRow(
                    icon: "square.stack.fill",
                    iconColor: .blue,
                    label: "Quantity: \(qty)"
                )
            }

            // Subtitle if present
            if let subtitle = item.subtitle {
                detailRow(
                    icon: "info.circle",
                    iconColor: .secondary,
                    label: subtitle
                )
            }

            Divider()

            // Hint
            Text("Tap to select")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(minWidth: 200, maxWidth: 280)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var iconForPopover: some View {
        if let icon = item.icon {
            switch icon {
            case .sfSymbol(let name, let color):
                Image(systemName: name)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: 20))
            case .none:
                EmptyView()
            }
        }
    }

    private func bucIcon(_ buc: SelectionItem.BUCIndicator) -> String {
        switch buc {
        case .blessed: return "sparkles"
        case .cursed: return "exclamationmark.triangle"
        case .uncursed: return "checkmark.circle"
        case .none: return "questionmark"
        }
    }

    private func bucColor(_ buc: SelectionItem.BUCIndicator) -> Color {
        switch buc {
        case .blessed: return .green
        case .cursed: return .red
        case .uncursed: return .yellow
        case .none: return .gray
        }
    }

    private func bucLabel(_ buc: SelectionItem.BUCIndicator) -> String {
        switch buc {
        case .blessed: return "Blessed"
        case .cursed: return "Cursed"
        case .uncursed: return "Uncursed"
        case .none: return "Unknown"
        }
    }

    @ViewBuilder
    private func detailRow(icon: String, iconColor: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(iconColor)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Unified Close Button

/// Animated close button with consistent press feedback
private struct UnifiedCloseButton: View {
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
        .frame(minWidth: 44, minHeight: 44)  // 44pt touch target (SWIFTUI-HIG-001)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(reduceMotion ? nil : AnimationConstants.pressAnimation, value: isPressed)
    }
}

// MARK: - Convenience Extensions

extension SelectionConfiguration {
    
    /// Create configuration from ItemSelectionContext
    /// Provides backwards compatibility for existing code
    static func fromItemContext(
        _ context: ItemSelectionContext,
        items: [NetHackItem],
        groundItems: [GameObjectInfo] = [],
        onSelect: @escaping (Character) -> Void,
        onSelectGround: ((UInt32) -> Void)? = nil
    ) -> SelectionConfiguration {
        var sections: [SelectionSection] = []
        
        // Apply filter to get matching items
        let matchingItems: [NetHackItem] = {
            guard let filter = context.filter else { return items }
            return items.filter(filter)
        }()
        
        // Filter ground items by category
        let matchingGroundItems: [GameObjectInfo] = {
            guard context.filter != nil else { return groundItems }
            return groundItems.filter { obj in
                switch context.categoryName {
                case "food": return obj.isFood
                case "potion": return obj.isPotion
                case "scroll or book":
                    return obj.objectClass == GameObjectInfo.SCROLL_CLASS ||
                           obj.objectClass == GameObjectInfo.SPBOOK_CLASS
                case "wand": return obj.objectClass == GameObjectInfo.WAND_CLASS
                case "armor": return obj.objectClass == GameObjectInfo.ARMOR_CLASS
                case "weapon": return obj.objectClass == GameObjectInfo.WEAPON_CLASS
                case "ring or amulet":
                    return obj.objectClass == GameObjectInfo.RING_CLASS ||
                           obj.objectClass == GameObjectInfo.AMULET_CLASS
                case "tool": return obj.objectClass == GameObjectInfo.TOOL_CLASS
                default: return true
                }
            }
        }()
        
        // Other items (fallback section)
        let otherItems: [NetHackItem] = {
            guard context.supportsFallback, let filter = context.filter else { return [] }
            return items.filter { !filter($0) }
        }()
        
        // Section 1: Ground items
        if !matchingGroundItems.isEmpty {
            let groundSection = SelectionSection(
                header: "Here",
                headerIcon: "arrow.down.circle",
                headerColor: .green,
                items: matchingGroundItems.map { obj in
                    SelectionItem.fromGroundItem(obj, accentColor: .green) {
                        onSelectGround?(obj.objectID)
                    }
                }
            )
            sections.append(groundSection)
        }
        
        // Section 2: Matching inventory items
        if !matchingItems.isEmpty {
            let showHeader = !matchingGroundItems.isEmpty || !otherItems.isEmpty
            let inventorySection = SelectionSection(
                header: showHeader ? context.categoryName.capitalized : nil,
                headerIcon: showHeader ? context.icon : nil,
                headerColor: context.color,
                items: matchingItems.map { item in
                    SelectionItem.fromInventoryItem(item, accentColor: context.color) {
                        onSelect(item.invlet)
                    }
                }
            )
            sections.append(inventorySection)
        }
        
        // Section 3: Other items (fallback)
        if !otherItems.isEmpty {
            let otherSection = SelectionSection(
                header: "Other",
                headerIcon: "questionmark.circle",
                headerColor: .orange,
                items: otherItems.map { item in
                    SelectionItem.fromInventoryItem(item, accentColor: .orange) {
                        onSelect(item.invlet)
                    }
                }
            )
            sections.append(otherSection)
        }
        
        return SelectionConfiguration(
            prompt: context.prompt,
            icon: context.icon,
            color: context.color,
            sections: sections,
            emptyMessage: context.emptyMessage
        )
    }
    
    /// Create configuration from TextInputContext
    /// Provides backwards compatibility for existing code
    static func fromTextContext(
        _ context: TextInputContext,
        onSubmit: @escaping (String) -> Void
    ) -> SelectionConfiguration {
        var sections: [SelectionSection] = []

        // Special handling for wishes - use categorized suggestions
        if context.prompt.contains("wish") {
            for category in TextInputContext.categorizedWishes {
                let categorySection = SelectionSection(
                    header: category.name,
                    headerIcon: category.icon,
                    headerColor: category.color,
                    items: category.items.map { suggestion in
                        SelectionItem.fromTextSuggestion(suggestion, accentColor: category.color) {
                            onSubmit(suggestion)
                        }
                    }
                )
                sections.append(categorySection)
            }
        } else if !context.staticSuggestions.isEmpty {
            // Section 1: Static suggestions (engrave options, etc.)
            let staticSection = SelectionSection(
                header: "Quick Options",
                headerIcon: nil,
                headerColor: context.color,
                items: context.staticSuggestions.map { suggestion in
                    SelectionItem.fromTextSuggestion(suggestion, accentColor: context.color) {
                        onSubmit(suggestion)
                    }
                }
            )
            sections.append(staticSection)
        }
        
        // Section 2: Defeated monsters (gold = achievement, safe choice)
        if !context.killedMonsters.isEmpty {
            let killedSection = SelectionSection(
                header: "Defeated (\(context.killedMonsters.count))",
                headerIcon: "trophy.fill",
                headerColor: .yellow,
                items: context.killedMonsters.map { monster in
                    SelectionItem.fromMonster(monster, accentColor: context.color) {
                        onSubmit(monster.name)
                    }
                }
            )
            sections.append(killedSection)
        }
        
        // Section 3: Encountered monsters (blue = informational, neutral)
        if !context.seenMonsters.isEmpty {
            let seenSection = SelectionSection(
                header: "Encountered (\(context.seenMonsters.count))",
                headerIcon: "eye.fill",
                headerColor: .cyan,
                items: context.seenMonsters.map { monster in
                    SelectionItem.fromMonster(monster, accentColor: context.color) {
                        onSubmit(monster.name)
                    }
                }
            )
            sections.append(seenSection)
        }
        
        // Dynamic placeholder based on context type
        let placeholder = context.prompt.contains("wish")
            ? "Search or type custom wish..."
            : "Search..."

        return SelectionConfiguration(
            prompt: context.prompt,
            icon: context.icon,
            color: context.color,
            sections: sections,
            showSearch: context.showSearch,
            searchPlaceholder: placeholder,
            showCustomInput: true,
            customInputPlaceholder: context.placeholder,
            emptyMessage: "No suggestions available.",
            onCustomSubmit: onSubmit
        )
    }
}

// MARK: - Preview

#if DEBUG
struct UnifiedSelectionSheet_Previews: PreviewProvider {
    static var previews: some View {
        // Item Selection Preview
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            UnifiedSelectionSheet(
                config: SelectionConfiguration(
                    prompt: "What do you want to eat?",
                    icon: "fork.knife",
                    color: .orange,
                    sections: [
                        SelectionSection(
                            header: "Food",
                            headerIcon: "fork.knife",
                            headerColor: .orange,
                            items: [
                                SelectionItem(
                                    id: "1",
                                    displayText: "apple",
                                    subtitle: nil,
                                    badge: .letter("a"),
                                    icon: .sfSymbol("fork.knife", .mint),
                                    bucIndicator: .blessed,
                                    quantity: 3,
                                    accentColor: .orange,
                                    onSelect: {}
                                ),
                                SelectionItem(
                                    id: "2",
                                    displayText: "food ration",
                                    subtitle: nil,
                                    badge: .letter("b"),
                                    icon: .sfSymbol("fork.knife", .mint),
                                    bucIndicator: .none,
                                    quantity: nil,
                                    accentColor: .orange,
                                    onSelect: {}
                                )
                            ]
                        )
                    ],
                    emptyMessage: "You have nothing to eat."
                ),
                onDismiss: {}
            )
        }
        .previewDisplayName("Item Selection")
        .previewInterfaceOrientation(.landscapeLeft)
        .preferredColorScheme(.dark)
        
        // Text Input Preview
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.1), Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            UnifiedSelectionSheet(
                config: SelectionConfiguration(
                    prompt: "What monster do you want to genocide?",
                    icon: "xmark.circle.fill",
                    color: .red,
                    sections: [
                        SelectionSection(
                            header: "Killed (5)",
                            headerIcon: "checkmark.circle.fill",
                            headerColor: .red,
                            items: [
                                SelectionItem.fromTextSuggestion("goblin", subtitle: "Killed 12", accentColor: .red, onSelect: {}),
                                SelectionItem.fromTextSuggestion("orc", subtitle: "Killed 8", accentColor: .red, onSelect: {})
                            ]
                        )
                    ],
                    showSearch: true,
                    showCustomInput: true,
                    customInputPlaceholder: "Enter monster name...",
                    onCustomSubmit: { _ in }
                ),
                onDismiss: {}
            )
        }
        .previewDisplayName("Text Input (Genocide)")
        .previewInterfaceOrientation(.landscapeLeft)
        .preferredColorScheme(.dark)
    }
}
#endif
