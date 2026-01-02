import SwiftUI

/// Centralized animation constants following iOS design guidelines
/// Ensures 120fps ProMotion performance and consistent feel across the app
///
/// Usage:
///   withAnimation(AnimationConstants.quickFeedback) { ... }
///   .animation(AnimationConstants.contentTransition, value: isExpanded)
enum AnimationConstants {

    // MARK: - Standard iOS Timings

    /// Quick feedback (0.15-0.25s) - For immediate tap acknowledgment
    /// Use for: Button press, toggle switches, selection highlights
    static let quickFeedback = Animation.easeInOut(duration: 0.2)

    /// Content transition (0.35-0.45s) - For expand/collapse, fade in/out
    /// Use for: Category expansion, menu opening, content reveals
    static let contentTransition = Animation.easeInOut(duration: 0.4)

    /// Modal transition (0.35-0.55s) - For full-screen modals
    /// Use for: ActionBook appear/dismiss, full-screen overlays
    static let modalTransition = Animation.easeInOut(duration: 0.45)

    /// Drag lift (0.20s) - For picking up draggable items
    /// Use for: Starting drag operations on actions/items
    static let dragLift = Animation.easeOut(duration: 0.2)

    /// Drop (0.30s) - For releasing dragged items
    /// Use for: Completing drag operations, returning to rest
    static let dragDrop = Animation.easeIn(duration: 0.3)

    // MARK: - Spring Animations (Natural Feel)

    /// Fast & snappy - For buttons, quick interactions
    /// response: 0.25s, dampingFraction: 0.7
    static let fastSnappy = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// Smooth & natural - For expand/collapse, content transitions
    /// response: 0.35s, dampingFraction: 0.75
    static let smoothNatural = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Bouncy feedback - For success states, confirmations
    /// response: 0.4s, dampingFraction: 0.5
    static let bouncyFeedback = Animation.spring(response: 0.4, dampingFraction: 0.5)

    /// Elastic return - For cancel/rejection, spring back
    /// stiffness: 300, damping: 20
    static let elasticReturn = Animation.interpolatingSpring(stiffness: 300, damping: 20)

    // MARK: - ActionBook Specific

    /// Category tab selection - Quick response
    static let categorySelection = Animation.spring(response: 0.25, dampingFraction: 0.7)

    /// Action item hover - Subtle feedback
    static let actionHover = Animation.easeInOut(duration: 0.2)

    /// Drag overlay - Instant visual feedback
    static let dragOverlay = Animation.easeInOut(duration: 0.15)

    /// Search filter - Smooth content change
    static let searchFilter = Animation.spring(response: 0.3, dampingFraction: 0.75)

    /// Book dismiss - Elegant exit
    static let bookDismiss = Animation.spring(response: 0.4, dampingFraction: 0.8)

    // MARK: - Staggered Animations

    /// Delay per item for staggered entrance (10ms for faster appearance)
    static let staggerDelay: TimeInterval = 0.01

    /// Staggered entrance animation for action items
    /// - Parameter index: Index of the item in the list
    /// - Parameter reduceMotion: Whether Reduce Motion is enabled
    /// - Returns: Animation with appropriate delay
    static func staggeredEntrance(index: Int, reduceMotion: Bool = false) -> Animation {
        let delay = reduceMotion ? 0 : Double(index) * staggerDelay
        return smoothNatural.delay(delay)
    }

    // MARK: - Transitions

    /// Slide from bottom with opacity fade (for ActionBook appearance)
    static let slideFromBottom = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
    )

    /// Slide from leading with opacity (for action items appearing)
    static let slideFromLeading = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .opacity
    )

    /// Scale and fade (for popovers, tooltips)
    static let scaleAndFade = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.8).combined(with: .opacity),
        removal: .opacity
    )

    /// Condition badge appear/disappear transition
    static let conditionBadgeTransition = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.3).combined(with: .opacity),
        removal: .scale(scale: 0.5).combined(with: .opacity)
    )

    // MARK: - Press & Hover Scale Effects

    /// Standard press scale for buttons (0.92 = subtle but noticeable)
    /// Use for: All tappable buttons, action items
    static let pressScale: CGFloat = 0.92

    /// Standard hover scale for cards/items (1.05 = lift effect)
    /// Use for: Inventory items, cards, hoverable elements
    static let hoverScale: CGFloat = 1.05

    // MARK: - Press Animations (reduceMotion-aware)

    /// Standard press animation for buttons
    static let pressAnimation = Animation.spring(duration: 0.15, bounce: 0.1)

    /// Standard press animation for toggle/checkbox feedback
    static let toggleFeedback = Animation.spring(duration: 0.15, bounce: 0.1)

    // MARK: - Turn-based Game Feedback

    /// Quick action confirmation (player moved, attacked, etc.)
    static let actionConfirmation = Animation.spring(duration: 0.15, bounce: 0.2)

    /// Status badge value change animation
    static let statusUpdate = Animation.spring(duration: 0.3, bounce: 0.1)

    /// Damage flash on health badge
    static let damageFlash = Animation.easeOut(duration: 0.1)

    /// Level transition (dramatic)
    static let levelTransition = Animation.spring(duration: 0.5, bounce: 0.15)

    // MARK: - Condition Badge Animations

    /// Standard condition badge appear (spring with natural bounce)
    static let conditionAppear = Animation.spring(response: 0.35, dampingFraction: 0.75)

    /// Critical condition appear (slower, more dramatic)
    static let conditionCriticalAppear = Animation.spring(response: 0.4, dampingFraction: 0.4)

    /// Condition removed/cured exit animation
    static let conditionExit = Animation.spring(response: 0.3, dampingFraction: 0.6)

    /// Critical badge pulse animation (for stoned, slimed, strangled, etc.)
    static let conditionCriticalPulse = Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)

    /// Hallucination rainbow hue rotation (continuous, slow)
    static let conditionHallucinationHue = Animation.linear(duration: 4.0).repeatForever(autoreverses: false)

    /// Condition badge reorder animation (when new conditions appear/disappear)
    static let conditionReorder = Animation.spring(response: 0.3, dampingFraction: 0.8)

    // MARK: - Condition Badge Scales

    /// Critical badge scale (8% larger than standard)
    static let conditionCriticalScale: CGFloat = 1.08

    /// Critical badge pulse scale (min/max for animation)
    static let conditionPulseScaleMin: CGFloat = 1.0
    static let conditionPulseScaleMax: CGFloat = 1.08

    // MARK: - Visual Feedback Durations

    /// How long to show "last used" highlight on action bar slot
    static let lastUsedHighlightDuration: TimeInterval = 0.2

    /// How long to show drag-over highlight
    static let dragOverHighlightDuration: TimeInterval = 0.15

    /// How long to show press effect
    static let pressEffectDuration: TimeInterval = 0.1

    /// Tooltip hover delay (match macOS/iOS standard)
    static let tooltipDelay: TimeInterval = 0.5

    // MARK: - Performance Guidelines

    /// Target frame rate for ProMotion displays
    static let targetFrameRate: Double = 120.0

    /// Maximum animation duration before it feels sluggish
    static let maxRecommendedDuration: TimeInterval = 0.6

    /// Cache timeout for action provider (balance freshness vs performance)
    static let actionCacheTimeout: TimeInterval = 1.0
}

// MARK: - Accessibility Extensions

extension AnimationConstants {

    /// Returns nil animation if Reduce Motion is enabled, otherwise the specified animation
    /// - Parameters:
    ///   - animation: The animation to use when Reduce Motion is disabled
    ///   - reduceMotion: Whether Reduce Motion accessibility setting is enabled
    /// - Returns: nil or the animation
    static func respectReduceMotion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Returns a simplified animation if Reduce Motion is enabled
    /// - Parameters:
    ///   - fullAnimation: Animation to use when Reduce Motion is disabled
    ///   - simplifiedAnimation: Simpler animation for Reduce Motion
    ///   - reduceMotion: Whether Reduce Motion accessibility setting is enabled
    /// - Returns: Appropriate animation
    static func adaptForReduceMotion(
        _ fullAnimation: Animation,
        simplified simplifiedAnimation: Animation = .linear(duration: 0.2),
        reduceMotion: Bool
    ) -> Animation {
        reduceMotion ? simplifiedAnimation : fullAnimation
    }
}

// MARK: - SwiftUI View Extension for Easy Access

extension View {

    /// Applies standard ActionBook entrance animation
    func actionBookEntrance(isPresented: Bool) -> some View {
        self
            .transition(AnimationConstants.slideFromBottom)
            .animation(AnimationConstants.modalTransition, value: isPresented)
    }

    /// Applies staggered entrance for action items
    /// - Parameters:
    ///   - index: Item index for stagger calculation
    ///   - isVisible: Whether item should be visible
    ///   - reduceMotion: Accessibility setting
    func actionItemEntrance(index: Int, isVisible: Bool, reduceMotion: Bool = false) -> some View {
        self
            .transition(AnimationConstants.slideFromLeading)
            .animation(
                AnimationConstants.staggeredEntrance(index: index, reduceMotion: reduceMotion),
                value: isVisible
            )
    }

    /// Applies hover effect with standard timing
    /// - Parameter isHovered: Whether item is hovered
    func actionHoverEffect(isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(AnimationConstants.actionHover, value: isHovered)
    }

    /// Applies drag-over highlight effect
    /// - Parameter isDraggedOver: Whether item has drag hovering over it
    func dragOverEffect(isDraggedOver: Bool) -> some View {
        self
            .scaleEffect(isDraggedOver ? 1.1 : 1.0)
            .animation(AnimationConstants.dragOverlay, value: isDraggedOver)
    }

    /// Applies condition badge entrance animation with reduce motion support
    /// - Parameters:
    ///   - isCritical: Whether this is a critical condition (tier 1)
    ///   - reduceMotion: Accessibility setting
    func conditionBadgeEntrance(isCritical: Bool, reduceMotion: Bool) -> some View {
        self
            .transition(AnimationConstants.conditionBadgeTransition)
            .animation(
                reduceMotion ? nil : (isCritical ? AnimationConstants.conditionCriticalAppear : AnimationConstants.conditionAppear),
                value: isCritical
            )
    }

    /// Applies critical condition pulse effect
    /// - Parameters:
    ///   - isPulsing: Whether pulse animation should be active
    ///   - reduceMotion: Accessibility setting - disables continuous animation
    @ViewBuilder
    func conditionCriticalPulse(isPulsing: Bool, reduceMotion: Bool) -> some View {
        if isPulsing && !reduceMotion {
            self
                .modifier(CriticalConditionPulseModifier())
        } else if isPulsing && reduceMotion {
            // Reduce Motion: static accent border instead of pulse
            self.overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.red.opacity(0.8), lineWidth: 2)
            )
        } else {
            self
        }
    }

    /// Applies hallucination rainbow hue rotation
    /// - Parameters:
    ///   - isActive: Whether hallucination effect should be active
    ///   - reduceMotion: Accessibility setting - disables continuous animation
    @ViewBuilder
    func conditionHallucinationEffect(isActive: Bool, reduceMotion: Bool) -> some View {
        if isActive && !reduceMotion {
            self.modifier(HallucinationHueModifier())
        } else if isActive && reduceMotion {
            // Reduce Motion: static purple tint instead of rotation
            self.overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.3))
            )
        } else {
            self
        }
    }
}

// MARK: - Condition Animation Modifiers

/// Modifier for critical condition pulse animation
private struct CriticalConditionPulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? AnimationConstants.conditionPulseScaleMax : AnimationConstants.conditionPulseScaleMin)
            .shadow(
                color: .red.opacity(isPulsing ? 0.6 : 0.2),
                radius: isPulsing ? 8 : 2
            )
            .animation(AnimationConstants.conditionCriticalPulse, value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}

/// Modifier for hallucination rainbow hue rotation
private struct HallucinationHueModifier: ViewModifier {
    @State private var hueRotation: Double = 0

    func body(content: Content) -> some View {
        content
            .hueRotation(.degrees(hueRotation))
            .animation(AnimationConstants.conditionHallucinationHue, value: hueRotation)
            .onAppear {
                hueRotation = 360
            }
    }
}

// MARK: - Equipment Panel Animations

extension AnimationConstants {
    /// Panel slide in from right edge - spring with subtle bounce (Ref: SWIFTUI-A-001)
    static let panelSlideIn = Animation.spring(duration: 0.35, bounce: 0.12)

    /// Panel slide out - faster, no bounce for clean exit
    static let panelSlideOut = Animation.spring(duration: 0.28, bounce: 0)

    /// Backdrop fade animation
    static let backdropFade = Animation.easeOut(duration: 0.25)

    /// Equipment slot tap feedback
    static let slotTapFeedback = Animation.spring(duration: 0.15, bounce: 0.1)

    /// Item equip/unequip "pop" effect
    static let itemEquipPop = Animation.spring(duration: 0.3, bounce: 0.2)

    /// Cursed item glow pulse cycle (1.2s for dramatic effect)
    static let cursedPulseCycle = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)

    // MARK: - Equipment Panel Thresholds

    /// Distance threshold to trigger dismiss (100pt)
    static let panelDismissThreshold: CGFloat = 100

    /// Velocity threshold to trigger dismiss (300pt/s)
    static let panelDismissVelocity: CGFloat = 300

    // MARK: - Equipment Panel Transitions

    /// Asymmetric slide from right with opacity (Ref: SWIFTUI-A-003)
    static let panelSlideFromRight = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    // MARK: - Inline Item Selection Animations

    /// Content swap between equipment list and item selection (zero bounce for clean swap)
    static let inlineContentSwap = Animation.spring(duration: 0.30, bounce: 0)

    /// Stagger delay for item card entrance (8ms per item for fast cascade)
    static let itemSelectionStagger: TimeInterval = 0.008

    /// Individual item card entrance animation
    static let itemCardEntrance = Animation.spring(duration: 0.25, bounce: 0.12)

    /// Item card press feedback (quick response)
    static let itemCardPress = Animation.spring(duration: 0.12, bounce: 0.1)

    /// Back button slide-in animation
    static let backButtonSlide = Animation.spring(duration: 0.20, bounce: 0.1)

    /// Paper doll dimming during item selection
    static let paperDollDim = Animation.easeOut(duration: 0.25)

    // MARK: - Inline Item Selection Scales

    /// Item card press scale (94% - subtle but responsive)
    static let itemCardPressScale: CGFloat = 0.94

    /// Paper doll dimmed opacity during selection mode
    static let paperDollDimmedOpacity: Double = 0.6

    // MARK: - Inline Item Selection Transitions

    /// Equipment list exit transition (slides left, fades)
    static let equipmentListExit = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    /// Item selection entrance transition (slides from right)
    static let itemSelectionEntrance = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )
}

// MARK: - Item Selection Sheet Animations

extension AnimationConstants {

    // MARK: - Sheet Appearance/Dismissal

    /// Sheet slide-in from bottom with slight scale (premium feel)
    /// Duration: 350ms, bounce: 0.1 - smooth but responsive
    /// Use for: ItemSelectionSheet, SpellSelectionSheet modal appearance
    static let sheetAppear = Animation.spring(duration: 0.35, bounce: 0.1)

    /// Sheet dismissal - faster, zero bounce for clean exit
    /// Duration: 280ms, bounce: 0 - quick and decisive
    static let sheetDismiss = Animation.spring(duration: 0.28, bounce: 0)

    /// Backdrop fade for sheet overlays (slightly faster than panel backdrop)
    static let sheetBackdropFade = Animation.easeOut(duration: 0.22)

    // MARK: - Item Card Stagger Entrance

    /// Stagger delay per item card (6ms - fast cascade, premium feel)
    /// Slightly faster than equipment panel (8ms) since item lists can be longer
    static let itemCardStaggerDelay: TimeInterval = 0.006

    /// Base entrance animation for individual item cards
    /// Duration: 220ms, bounce: 0.1 - snappy with subtle life
    static let itemCardBaseEntrance = Animation.spring(duration: 0.22, bounce: 0.1)

    /// Staggered item card entrance with index-based delay
    /// - Parameter index: Index of card in the list
    /// - Parameter reduceMotion: Accessibility setting
    /// - Returns: Animation with appropriate delay for cascade effect
    static func itemCardStaggeredEntrance(index: Int, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0.15) }
        let delay = Double(index) * itemCardStaggerDelay
        return itemCardBaseEntrance.delay(delay)
    }

    /// Item card hover/highlight scale for selection preview
    static let itemCardHoverScale: CGFloat = 1.02

    // MARK: - Category Filter Animations

    /// Category filter chip selection animation
    /// Duration: 250ms, bounce: 0.12 - responsive with subtle bounce
    static let categoryFilterSelect = Animation.spring(duration: 0.25, bounce: 0.12)

    /// Category content transition when filter changes
    /// Duration: 300ms, bounce: 0 - smooth content swap
    static let categoryContentSwap = Animation.spring(duration: 0.30, bounce: 0)

    /// Filter chip scale when selected (102% - subtle emphasis)
    static let categoryFilterSelectedScale: CGFloat = 1.02

    // MARK: - Selection Confirmation Feedback

    /// Selection confirmation "pop" animation
    /// Duration: 200ms, bounce: 0.25 - celebratory but not excessive
    /// Use for: Successful item selection before dismissal
    static let selectionConfirmation = Animation.spring(duration: 0.20, bounce: 0.25)

    /// Selection confirmation scale (108% - noticeable success feedback)
    static let selectionConfirmationScale: CGFloat = 1.08

    /// Selection checkmark/icon appear animation
    static let selectionIconAppear = Animation.spring(duration: 0.25, bounce: 0.3)

    // MARK: - Empty State Animations

    /// Empty state fade-in animation (gentle reveal)
    /// Duration: 400ms with 100ms delay - allows sheet to settle first
    static let emptyStateFadeIn = Animation.easeOut(duration: 0.4).delay(0.1)

    /// Empty state icon scale animation (from 0.8 to 1.0)
    static let emptyStateIconScale = Animation.spring(duration: 0.5, bounce: 0.15)

    /// Empty state initial icon scale (starts smaller for grow-in effect)
    static let emptyStateIconInitialScale: CGFloat = 0.8

    // MARK: - Sheet Transitions

    /// Sheet appearance transition (slide + scale + opacity for premium feel)
    static let sheetAppearTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom)
            .combined(with: .scale(scale: 0.95, anchor: .bottom))
            .combined(with: .opacity),
        removal: .move(edge: .bottom)
            .combined(with: .opacity)
    )

    /// Sheet content fade transition (for content changes within sheet)
    static let sheetContentFade = AnyTransition.opacity

    /// Item card entrance transition (slide from bottom + fade)
    static let itemCardEntranceTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .opacity
    )

    // MARK: - Haptic Feedback Points (Documentation)

    /// Haptic feedback recommendations for ItemSelectionSheet:
    ///
    /// 1. Sheet Appear: `.impact(weight: .light)` - subtle acknowledgment
    /// 2. Item Card Tap: `.selection()` - standard selection feedback
    /// 3. Item Selected: `.impact(weight: .medium)` - confirmation
    /// 4. Sheet Dismiss (cancel): `.impact(weight: .light)` - dismissal acknowledgment
    /// 5. Category Filter Tap: `.selection()` - filter change
    /// 6. Empty State: None - no haptic for passive states
    ///
    /// Implementation:
    /// ```swift
    /// .sensoryFeedback(.impact(weight: .light), trigger: isPresented)
    /// .sensoryFeedback(.selection, trigger: selectedFilter)
    /// ```

    // MARK: - Performance Constants

    /// Maximum items to animate with stagger (beyond this, use instant appear)
    /// Prevents frame drops on large inventories
    static let maxStaggeredItems: Int = 20

    /// Stagger cutoff - items beyond this index appear instantly
    static func shouldStaggerItem(at index: Int) -> Bool {
        index < maxStaggeredItems
    }
}

// MARK: - Item Selection Sheet View Extensions

extension View {

    /// Applies item selection sheet entrance animation
    /// - Parameters:
    ///   - isPresented: Whether sheet is presented
    ///   - reduceMotion: Accessibility setting
    func itemSelectionSheetEntrance(isPresented: Bool, reduceMotion: Bool) -> some View {
        self
            .transition(
                reduceMotion
                    ? .opacity
                    : AnimationConstants.sheetAppearTransition
            )
            .animation(
                reduceMotion ? nil : AnimationConstants.sheetAppear,
                value: isPresented
            )
    }

    /// Applies staggered entrance animation for item cards in grid/list
    /// - Parameters:
    ///   - index: Card index in the list
    ///   - isVisible: Whether card should be visible
    ///   - reduceMotion: Accessibility setting
    func itemCardStaggeredEntrance(index: Int, isVisible: Bool, reduceMotion: Bool) -> some View {
        self
            .transition(
                reduceMotion
                    ? .opacity
                    : AnimationConstants.itemCardEntranceTransition
            )
            .animation(
                AnimationConstants.shouldStaggerItem(at: index)
                    ? AnimationConstants.itemCardStaggeredEntrance(index: index, reduceMotion: reduceMotion)
                    : (reduceMotion ? nil : AnimationConstants.itemCardBaseEntrance),
                value: isVisible
            )
    }

    /// Applies press feedback animation for item selection cards
    /// - Parameters:
    ///   - isPressed: Whether card is being pressed
    ///   - reduceMotion: Accessibility setting
    func itemCardPressFeedback(isPressed: Bool, reduceMotion: Bool) -> some View {
        self
            .scaleEffect(isPressed ? AnimationConstants.itemCardPressScale : 1.0)
            .animation(
                reduceMotion ? nil : AnimationConstants.itemCardPress,
                value: isPressed
            )
    }

    /// Applies category filter selection animation
    /// - Parameters:
    ///   - isSelected: Whether filter is selected
    ///   - reduceMotion: Accessibility setting
    func categoryFilterAnimation(isSelected: Bool, reduceMotion: Bool) -> some View {
        self
            .scaleEffect(isSelected ? AnimationConstants.categoryFilterSelectedScale : 1.0)
            .animation(
                reduceMotion ? nil : AnimationConstants.categoryFilterSelect,
                value: isSelected
            )
    }

    /// Applies selection confirmation "pop" effect
    /// - Parameters:
    ///   - isConfirming: Whether confirmation animation should play
    ///   - reduceMotion: Accessibility setting
    func selectionConfirmationPop(isConfirming: Bool, reduceMotion: Bool) -> some View {
        self
            .scaleEffect(isConfirming ? AnimationConstants.selectionConfirmationScale : 1.0)
            .animation(
                reduceMotion ? nil : AnimationConstants.selectionConfirmation,
                value: isConfirming
            )
    }

    /// Applies empty state entrance animation (fade + scale)
    /// - Parameters:
    ///   - isVisible: Whether empty state is visible
    ///   - reduceMotion: Accessibility setting
    @ViewBuilder
    func emptyStateEntrance(isVisible: Bool, reduceMotion: Bool) -> some View {
        if reduceMotion {
            self.opacity(isVisible ? 1 : 0)
        } else {
            self
                .opacity(isVisible ? 1 : 0)
                .animation(AnimationConstants.emptyStateFadeIn, value: isVisible)
        }
    }
}

// MARK: - Empty State Icon Modifier

/// Modifier for animated empty state icon (scale-in effect)
/// Respects Reduce Motion accessibility setting (SWIFTUI-A-009)
struct EmptyStateIconModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                reduceMotion
                    ? 1.0
                    : (hasAppeared ? 1.0 : AnimationConstants.emptyStateIconInitialScale)
            )
            .opacity(hasAppeared ? 1 : 0)
            .onAppear {
                guard !reduceMotion else {
                    hasAppeared = true
                    return
                }
                withAnimation(AnimationConstants.emptyStateIconScale) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    /// Applies animated empty state icon effect (grow-in + fade)
    func emptyStateIconAnimation() -> some View {
        modifier(EmptyStateIconModifier())
    }
}

// MARK: - Cursed Item Glow Modifier

/// Pulsing red glow effect for cursed items (Ref: SWIFTUI-A-009 - respects Reduce Motion)
struct CursedItemGlowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var glowOpacity: CGFloat = 0.3

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.red.opacity(reduceMotion ? 0.5 : glowOpacity),
                radius: reduceMotion ? 4 : 8
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(AnimationConstants.cursedPulseCycle) {
                    glowOpacity = 0.7
                }
            }
    }
}

extension View {
    /// Apply cursed item glow effect (respects Reduce Motion)
    func cursedItemGlow() -> some View {
        modifier(CursedItemGlowModifier())
    }
}

// MARK: - Death Screen Animations

extension AnimationConstants {

    // MARK: - Death Screen Entrance (Staggered, <1s total)

    /// Skull icon entrance - dramatic drop with bounce
    /// bounce: 0.25 - more bounce than normal (death is impactful)
    static let deathSkullEntrance = Animation.spring(duration: 0.4, bounce: 0.25)

    /// "GAME OVER" title scale entrance
    static let deathTitleEntrance = Animation.spring(duration: 0.35, bounce: 0.1)

    /// Death message slide-up entrance
    static let deathMessageEntrance = Animation.smooth(duration: 0.3)

    /// Score card slide-in from right
    static let deathScoreCardEntrance = Animation.spring(duration: 0.35, bounce: 0.1)

    /// Individual stat card entrance
    static let deathStatEntrance = Animation.spring(duration: 0.25, bounce: 0.12)

    /// Buttons fade-in (no spring - shouldn't distract from content)
    static let deathButtonsEntrance = Animation.smooth(duration: 0.2)

    // MARK: - Death Screen Stagger Delays

    /// Total death screen entrance duration (~950ms)
    static let deathEntranceTotalDuration: TimeInterval = 0.95

    /// Skull entrance delay (immediate)
    static let deathSkullDelay: TimeInterval = 0.0

    /// Title entrance delay
    static let deathTitleDelay: TimeInterval = 0.15

    /// Message entrance delay
    static let deathMessageDelay: TimeInterval = 0.30

    /// Score card entrance delay
    static let deathScoreCardDelay: TimeInterval = 0.45

    /// Stats base delay (before stagger)
    static let deathStatsBaseDelay: TimeInterval = 0.55

    /// Stats inter-item stagger (40ms between each)
    static let deathStatsStagger: TimeInterval = 0.04

    /// Buttons entrance delay
    static let deathButtonsDelay: TimeInterval = 0.70

    // MARK: - Death Screen Scale Values

    /// Skull initial scale (before entrance)
    static let deathSkullInitialScale: CGFloat = 0.4

    /// Title initial scale (before entrance)
    static let deathTitleInitialScale: CGFloat = 0.6

    /// Stat card initial scale (before entrance)
    static let deathStatInitialScale: CGFloat = 0.85

    /// Score card slide distance
    static let deathScoreCardSlideDistance: CGFloat = 60

    /// Skull drop distance
    static let deathSkullDropDistance: CGFloat = 50

    /// Message slide distance
    static let deathMessageSlideDistance: CGFloat = 15
}
