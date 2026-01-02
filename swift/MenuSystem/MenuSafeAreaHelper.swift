import SwiftUI

// MARK: - Menu Safe Area Insets
/// Custom safe area insets for menu components
/// Provides consistent padding for Dynamic Island and notch areas in landscape
struct MenuSafeAreaInsets: Equatable {
    let leading: CGFloat
    let trailing: CGFloat
    let bottom: CGFloat

    static let zero = MenuSafeAreaInsets(leading: 0, trailing: 0, bottom: 0)

    /// Minimum safe padding (16pt) when device safe area is less
    static let minimumHorizontal: CGFloat = 16
    static let minimumBottom: CGFloat = 16

    /// Create insets from GeometryProxy safe area
    /// Ensures minimum padding even when device reports zero
    init(from geometry: GeometryProxy) {
        let safeArea = geometry.safeAreaInsets
        self.leading = max(safeArea.leading, Self.minimumHorizontal)
        self.trailing = max(safeArea.trailing, Self.minimumHorizontal)
        self.bottom = max(safeArea.bottom, Self.minimumBottom)
    }

    init(leading: CGFloat, trailing: CGFloat, bottom: CGFloat) {
        self.leading = leading
        self.trailing = trailing
        self.bottom = bottom
    }
}

// MARK: - Environment Key

private struct MenuSafeAreaKey: EnvironmentKey {
    static let defaultValue = MenuSafeAreaInsets.zero
}

extension EnvironmentValues {
    var menuSafeAreaInsets: MenuSafeAreaInsets {
        get { self[MenuSafeAreaKey.self] }
        set { self[MenuSafeAreaKey.self] = newValue }
    }
}

// MARK: - View Modifier

/// Modifier that provides menu-aware safe area insets to child views
struct MenuSafeAreaModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .environment(\.menuSafeAreaInsets, MenuSafeAreaInsets(from: geometry))
        }
    }
}

extension View {
    /// Apply menu-aware safe area insets via environment
    func menuSafeArea() -> some View {
        modifier(MenuSafeAreaModifier())
    }
}
