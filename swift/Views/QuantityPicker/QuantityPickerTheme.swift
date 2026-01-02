//
//  QuantityPickerTheme.swift
//  nethack
//
//  Modern theme for NetHack quantity picker optimized for iPad touch interaction
//

import SwiftUI

enum QuantityPickerTheme {
    // MARK: - Colors

    /// Background color for the picker sheet/popover
    static let backgroundColor = Color(UIColor.secondarySystemBackground)

    /// Main accent color for interactive elements
    static let accentColor = Color(red: 0.2, green: 0.6, blue: 0.8)

    /// Color for selected/active states
    static let activeColor = Color.blue

    /// Color for the slider track
    static let sliderTrackColor = Color.gray.opacity(0.3)

    /// Color for the slider fill
    static let sliderFillColor = accentColor

    /// Color for preset button backgrounds
    static let presetButtonBackground = Color(UIColor.tertiarySystemFill)

    /// Color for selected preset button
    static let presetButtonSelectedBackground = accentColor

    /// Text color for normal state
    static let textPrimary = Color.primary

    /// Text color for secondary information
    static let textSecondary = Color.secondary

    /// Destructive action color
    static let destructiveColor = Color.red

    // MARK: - Dimensions

    /// Standard padding between elements
    static let standardPadding: CGFloat = 16

    /// Compact padding for tight spaces
    static let compactPadding: CGFloat = 8

    /// Large padding for major sections
    static let largePadding: CGFloat = 24

    /// Height of the slider track
    static let sliderTrackHeight: CGFloat = 8

    /// Size of the slider thumb
    static let sliderThumbSize: CGFloat = 32

    /// Height of preset buttons
    static let presetButtonHeight: CGFloat = 44

    /// Minimum width for preset buttons
    static let presetButtonMinWidth: CGFloat = 60

    /// Corner radius for buttons
    static let buttonCornerRadius: CGFloat = 12

    /// Corner radius for the sheet/popover
    static let sheetCornerRadius: CGFloat = 20

    /// Maximum width for iPad popover
    static let popoverMaxWidth: CGFloat = 400

    /// Preferred height for the picker content
    static let preferredHeight: CGFloat = 280

    /// Height for direct input sheet
    static let directInputSheetHeight: CGFloat = 320

    // MARK: - Typography

    /// Font for the main quantity display
    static let quantityDisplayFont = Font.system(size: 48, weight: .bold, design: .rounded)

    /// Font for item name/description
    static let itemNameFont = Font.system(size: 18, weight: .medium)

    /// Font for preset button labels
    static let presetButtonFont = Font.system(size: 16, weight: .semibold)

    /// Font for secondary information
    static let secondaryFont = Font.system(size: 14, weight: .regular)

    /// Font for action buttons
    static let actionButtonFont = Font.system(size: 17, weight: .semibold)

    // MARK: - Animation

    /// Standard animation for UI transitions
    static let standardAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Quick animation for immediate feedback
    static let quickAnimation = Animation.spring(response: 0.2, dampingFraction: 0.8)

    /// Smooth animation for continuous movements
    static let smoothAnimation = Animation.easeInOut(duration: 0.3)

    // MARK: - Haptics

    /// Impact style for slider snap points
    static let snapImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle.light

    /// Impact style for button taps
    static let buttonImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle.medium

    /// Impact style for confirmations
    static let confirmationImpactStyle = UIImpactFeedbackGenerator.FeedbackStyle.heavy

    // MARK: - Layout

    /// Spacing between preset buttons
    static let presetButtonSpacing: CGFloat = 8

    /// Spacing between major sections
    static let sectionSpacing: CGFloat = 20

    /// Maximum number of preset buttons to show
    static let maxPresetButtons = 4

    /// Threshold for showing "All" button (if maxQuantity > this)
    static let showAllButtonThreshold = 10

    // MARK: - Accessibility

    /// Minimum touch target size for interactive elements
    static let minimumTouchTarget: CGFloat = 44

    /// Contrast ratio for text on backgrounds
    static let minimumContrastRatio: CGFloat = 4.5

    // MARK: - Device Adaptation

    /// Check if device is iPad
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Check if device is in landscape
    static var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    /// Get adaptive padding based on device
    static var adaptivePadding: CGFloat {
        isIPad ? largePadding : standardPadding
    }

    /// Get adaptive font size multiplier
    static var fontSizeMultiplier: CGFloat {
        isIPad ? 1.2 : 1.0
    }
}

// MARK: - Preset Quantity Calculations

extension QuantityPickerTheme {
    /// Calculate smart preset quantities based on max value
    static func calculatePresets(for maxQuantity: Int) -> [Int] {
        guard maxQuantity > 1 else { return [] }

        var presets: [Int] = []

        // Always include 1
        presets.append(1)

        // For small quantities, show every value
        if maxQuantity <= 5 {
            for i in 2...maxQuantity {
                presets.append(i)
            }
            return Array(presets.prefix(maxPresetButtons))
        }

        // For medium quantities, use strategic points
        if maxQuantity <= 20 {
            if maxQuantity >= 5 { presets.append(5) }
            if maxQuantity >= 10 { presets.append(10) }
            if maxQuantity > 10 { presets.append(maxQuantity) }
            return Array(presets.prefix(maxPresetButtons))
        }

        // For large quantities, use percentage-based
        presets.append(maxQuantity / 4)  // 25%
        presets.append(maxQuantity / 2)  // 50%
        if maxQuantity > showAllButtonThreshold {
            presets.append(maxQuantity)  // All
        }

        return Array(presets.prefix(maxPresetButtons))
    }

    /// Format quantity for display
    static func formatQuantity(_ quantity: Int, max: Int) -> String {
        if quantity == max && max > showAllButtonThreshold {
            return "All"
        }
        return "\(quantity)"
    }
}

// MARK: - Visual Effects

extension QuantityPickerTheme {
    /// Standard shadow for elevated elements
    static var standardShadow: some View {
        Color.black.opacity(0.15)
            .blur(radius: 8)
            .offset(y: 2)
    }

    /// Subtle shadow for buttons
    static var buttonShadow: some View {
        Color.black.opacity(0.1)
            .blur(radius: 4)
            .offset(y: 1)
    }

    /// Glass morphism background
    static var glassMorphismBackground: some ShapeStyle {
        .ultraThinMaterial
    }
}