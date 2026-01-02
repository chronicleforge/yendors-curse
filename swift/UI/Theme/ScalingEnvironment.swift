//
//  ScalingEnvironment.swift
//  nethack
//
//  RESPONSIVE LAYOUT SYSTEM - Works on ALL iOS devices
//
//  STRATEGY: Relative layout with minimum size guarantees
//  - NO uniform scaling (causes tiny UI on phones)
//  - Use percentage-based widths
//  - Minimum touch targets: 44pt (Apple HIG)
//  - Adaptive text with minimumScaleFactor
//
//  USAGE:
//  - Use ResponsiveLayout.contentWidth(in:) for card widths
//  - Use ResponsiveLayout.fontSize(:for:) for text
//  - Use DeviceCategory for device-specific adjustments
//

import SwiftUI

// MARK: - Device Category (Simple, Reliable)

/// Device category based on screen size class
/// Avoids complex breakpoints - just 3 categories
enum DeviceCategory {
    case phone          // iPhone SE to iPhone Pro Max
    case tabletCompact  // iPad in slide-over or small window
    case tablet         // iPad full screen

    /// Detect device category from geometry
    static func detect(for geometry: GeometryProxy) -> DeviceCategory {
        let width = geometry.size.width
        let height = geometry.size.height
        let smallerDimension = min(width, height)

        // iPad slide-over is ~320pt wide
        // iPhone Pro Max is 430pt wide
        // iPad mini portrait is 744pt wide
        guard smallerDimension >= 500 else {
            return .phone
        }

        // Check if iPad is in compact mode (slide-over, split view)
        guard width >= 600 else {
            return .tabletCompact
        }

        return .tablet
    }

    /// Is this a phone-sized device?
    var isPhone: Bool {
        self == .phone
    }

    /// Is this a tablet (any size)?
    var isTablet: Bool {
        self != .phone
    }
}

// MARK: - Responsive Layout System

/// Responsive layout helpers that work on ALL devices
/// NO uniform scaling - uses relative sizing instead
struct ResponsiveLayout {

    // MARK: - Content Width (Percentage-Based)

    /// Calculate content width as percentage of available space
    /// - Parameters:
    ///   - geometry: Current geometry
    ///   - percentage: Desired percentage (0.0-1.0), default 0.9
    ///   - maxWidth: Maximum width cap (for large screens)
    /// - Returns: Calculated width
    static func contentWidth(
        in geometry: GeometryProxy,
        percentage: CGFloat = 0.9,
        maxWidth: CGFloat = 800
    ) -> CGFloat {
        let available = geometry.size.width
        let calculated = available * percentage
        return min(calculated, maxWidth)
    }

    /// Content width for hero cards (main character display)
    static func heroCardWidth(in geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:
            // Use almost full width on phones
            return geometry.size.width - 32  // 16pt padding each side
        case .tabletCompact:
            return geometry.size.width - 48
        case .tablet:
            // Cap width on large tablets
            return min(geometry.size.width * 0.7, 700)
        }
    }

    // MARK: - Font Sizes (Device-Aware)

    /// Font size that adapts to device category
    /// Always readable, never too small
    enum FontStyle {
        case title      // Main screen titles
        case headline   // Card titles, section headers
        case body       // Regular text
        case caption    // Secondary text
        case footnote   // Smallest readable text
    }

    /// Get appropriate font size for device
    static func fontSize(_ style: FontStyle, for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch (style, device) {
        // Title - large, prominent
        case (.title, .phone):      return 32
        case (.title, .tabletCompact): return 40
        case (.title, .tablet):     return 48

        // Headline - card titles
        case (.headline, .phone):   return 18
        case (.headline, .tabletCompact): return 20
        case (.headline, .tablet):  return 22

        // Body - regular text
        case (.body, .phone):       return 15
        case (.body, .tabletCompact): return 16
        case (.body, .tablet):      return 17

        // Caption - secondary
        case (.caption, .phone):    return 13
        case (.caption, .tabletCompact): return 14
        case (.caption, .tablet):   return 14

        // Footnote - smallest
        case (.footnote, .phone):   return 11
        case (.footnote, .tabletCompact): return 12
        case (.footnote, .tablet):  return 12
        }
    }

    // MARK: - Spacing (Device-Aware)

    enum SpacingSize {
        case large
        case medium
        case small
        case tiny
    }

    static func spacing(_ size: SpacingSize, for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch (size, device) {
        case (.large, .phone):      return 20
        case (.large, .tabletCompact): return 28
        case (.large, .tablet):     return 32

        case (.medium, .phone):     return 14
        case (.medium, .tabletCompact): return 18
        case (.medium, .tablet):    return 20

        case (.small, .phone):      return 8
        case (.small, .tabletCompact): return 10
        case (.small, .tablet):     return 12

        case (.tiny, .phone):       return 4
        case (.tiny, .tabletCompact): return 6
        case (.tiny, .tablet):      return 8
        }
    }

    // MARK: - Padding (Device-Aware)

    static func screenPadding(for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:        return 16
        case .tabletCompact: return 20
        case .tablet:       return 32
        }
    }

    static func cardPadding(for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:        return 12
        case .tabletCompact: return 16
        case .tablet:       return 20
        }
    }

    // MARK: - Touch Targets (MINIMUM 44pt - Apple HIG)

    /// Minimum touch target size (Apple HIG requirement)
    static let minimumTouchTarget: CGFloat = 44

    /// Button height that meets accessibility requirements
    static func buttonHeight(for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:        return 48  // Slightly larger for easier tapping
        case .tabletCompact: return 50
        case .tablet:       return 56
        }
    }

    // MARK: - Corner Radius (Device-Aware)

    static func cornerRadius(for geometry: GeometryProxy) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:        return 12
        case .tabletCompact: return 16
        case .tablet:       return 20
        }
    }
}

// MARK: - Environment Key for Device Category

private struct DeviceCategoryKey: EnvironmentKey {
    static let defaultValue: DeviceCategory = .tablet
}

extension EnvironmentValues {
    var deviceCategory: DeviceCategory {
        get { self[DeviceCategoryKey.self] }
        set { self[DeviceCategoryKey.self] = newValue }
    }
}

// MARK: - View Modifier for Responsive Context

extension View {
    /// Apply responsive context to view hierarchy
    /// Child views can read `@Environment(\.deviceCategory)`
    func responsiveContext(in geometry: GeometryProxy) -> some View {
        let category = DeviceCategory.detect(for: geometry)
        return self.environment(\.deviceCategory, category)
    }
}

// MARK: - Legacy Compatibility (ScalingEnvironment)

/// Legacy scaling environment - DEPRECATED
/// Use ResponsiveLayout instead for new code
struct ScalingEnvironment {
    // MARK: - Reference Device (iPad Pro 13" Landscape)
    // We design for the largest device and scale down
    static let referenceWidth: CGFloat = 1366   // iPad Pro 13" landscape width
    static let referenceHeight: CGFloat = 1024  // iPad Pro 13" landscape height

    // Alternative: iPad Pro 13" Portrait
    static let referencePortraitWidth: CGFloat = 1024
    static let referencePortraitHeight: CGFloat = 1366

    // iPhone Reference Dimensions (for better scaling calculations)
    // iPhone 15 Pro Max (largest current iPhone)
    static let iPhoneReferenceWidth: CGFloat = 430   // Portrait width
    static let iPhoneReferenceHeight: CGFloat = 932  // Portrait height

    // MARK: - Device Detection

    /// Proper device detection using UIDevice (more reliable than size checks)
    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Size-based device detection for GeometryProxy context
    /// Fallback when UIDevice check is not appropriate
    static func isPhone(for geometry: GeometryProxy) -> Bool {
        DeviceCategory.detect(for: geometry).isPhone
    }

    // MARK: - IMPROVED Scale Factor Calculation

    /// Calculate scale factor with BETTER minimum for phones
    /// Uses device-aware calculation instead of raw math
    static func scaleFactor(for geometry: GeometryProxy, minimum: CGFloat = 0.3) -> CGFloat {
        let device = DeviceCategory.detect(for: geometry)

        switch device {
        case .phone:
            // For phones: Use a reasonable scale that keeps UI usable
            // Don't calculate from iPad reference - just use a good value
            return max(0.55, minimum)  // 55% is minimum for readability

        case .tabletCompact:
            // Compact tablet: moderate scaling
            let isLandscape = geometry.size.width > geometry.size.height
            let refWidth = isLandscape ? referenceWidth : referencePortraitWidth
            let scale = geometry.size.width / refWidth
            return max(scale, 0.5)

        case .tablet:
            // Full tablet: calculate normally
            let isLandscape = geometry.size.width > geometry.size.height
            let refWidth = isLandscape ? referenceWidth : referencePortraitWidth
            let refHeight = isLandscape ? referenceHeight : referencePortraitHeight
            let widthScale = geometry.size.width / refWidth
            let heightScale = geometry.size.height / refHeight
            return max(min(widthScale, heightScale), minimum)
        }
    }

    // MARK: - Fixed Sizes (Designed for iPad Pro 13")
    // These are the ONLY sizes used throughout the app

    struct Fonts {
        static let title: CGFloat = 56        // Main title
        static let subtitle: CGFloat = 20     // Subtitles
        static let body: CGFloat = 17         // Body text
        static let caption: CGFloat = 14      // Small text
        static let tiny: CGFloat = 11         // Tiny labels
    }

    struct Spacing {
        static let huge: CGFloat = 48
        static let large: CGFloat = 32
        static let medium: CGFloat = 20
        static let small: CGFloat = 12
        static let tiny: CGFloat = 8
    }

    struct Cards {
        static let mainHeroHeight: CGFloat = 320
        static let mainHeroAspectRatio: CGFloat = 2.2  // Width/Height for landscape
        static let cornerRadius: CGFloat = 20
        static let shadowRadius: CGFloat = 10
    }

    struct Padding {
        static let screen: CGFloat = 32       // Screen edge padding
        static let card: CGFloat = 20         // Internal card padding
        static let button: CGFloat = 16       // Button internal padding
    }

    // MARK: - Device-Aware UI Scaling

    /// UI scale multiplier for iPhone vs iPad
    /// iPhone screens are smaller, so UI elements should scale down proportionally
    struct UIScale {
        /// Navigation control wheel size multiplier
        static func navigationWheelSize(isPhone: Bool) -> CGFloat {
            isPhone ? 180 : 280  // ~36% smaller on iPhone
        }

        /// Action bar button size multiplier
        static func actionButtonSize(isPhone: Bool, compact: Bool) -> CGFloat {
            if isPhone {
                return compact ? 50 : 60  // ~29% smaller on iPhone
            } else {
                return compact ? 70 : 85
            }
        }

        /// Context overlay card width
        static func contextCardWidth(isPhone: Bool) -> CGFloat {
            isPhone ? 220 : 300  // ~27% smaller on iPhone
        }

        /// Status badge font size
        static func statusBadgeFontSize(isPhone: Bool) -> CGFloat {
            isPhone ? 11 : 14  // ~21% smaller on iPhone
        }

        /// Status badge icon size
        static func statusBadgeIconSize(isPhone: Bool) -> CGFloat {
            isPhone ? 13 : 16  // ~19% smaller on iPhone
        }

        /// Magnifying glass button size
        static func magnifyingGlassSize(isPhone: Bool) -> CGFloat {
            isPhone ? 55 : 70  // ~21% smaller on iPhone
        }

        /// Magnifying glass icon size
        static func magnifyingGlassIconSize(isPhone: Bool) -> CGFloat {
            isPhone ? 28 : 36  // ~22% smaller on iPhone
        }

        /// Inspection overlay card width
        static func inspectionCardWidth(isPhone: Bool) -> CGFloat {
            isPhone ? 200 : 280  // ~29% smaller on iPhone
        }

        /// Message overlay font size
        static func messageFontSize(isPhone: Bool) -> CGFloat {
            isPhone ? 13 : 16  // ~19% smaller on iPhone
        }

        /// Message overlay max width
        static func messageMaxWidth(isPhone: Bool) -> CGFloat {
            isPhone ? 250 : 400  // ~37% smaller on iPhone
        }

        /// Screen edge padding (dynamic for smaller screens)
        static func screenPadding(isPhone: Bool) -> CGFloat {
            isPhone ? 12 : 20  // ~40% less padding on iPhone
        }
    }
}

// MARK: - Environment Key for Game Scale Factor (Legacy)

private struct GameScaleFactorKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var gameScaleFactor: CGFloat {
        get { self[GameScaleFactorKey.self] }
        set { self[GameScaleFactorKey.self] = newValue }
    }
}

// MARK: - Debug Helper

extension ScalingEnvironment {
    /// Debug information for current scaling
    static func debugInfo(for geometry: GeometryProxy) -> String {
        let scale = scaleFactor(for: geometry)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let category = DeviceCategory.detect(for: geometry)

        return """
        Device: \(device)
        Category: \(category)
        Screen: \(Int(geometry.size.width))x\(Int(geometry.size.height))
        Scale: \(String(format: "%.2f", scale))
        """
    }
}