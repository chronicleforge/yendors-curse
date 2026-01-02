import SwiftUI
import Combine

// MARK: - Menu Router
/// Routes menu contexts to appropriate views (specialized or default)
/// Singleton pattern for app-wide registration
@MainActor
final class MenuRouter: ObservableObject {

    // MARK: - Singleton

    static let shared = MenuRouter()

    // MARK: - Types

    /// Builder closure that creates a view from context
    typealias ViewBuilder = @MainActor (NHMenuContext) -> AnyView

    /// Selection handler closure
    typealias SelectionHandler = @MainActor ([NHMenuSelection]) -> Void

    // MARK: - Properties

    /// Registry of specialized view builders by menu ID
    private var specializations: [String: ViewBuilder] = [:]

    /// Current active menu context
    @Published var activeContext: NHMenuContext?

    /// Whether a menu is currently showing
    @Published var isShowingMenu: Bool = false

    /// Completion handler for current menu
    private var currentCompletion: SelectionHandler?

    // MARK: - Init

    private init() {
        registerDefaultSpecializations()
    }

    // MARK: - Registration

    /// Register a specialized view builder for a menu ID
    /// - Parameters:
    ///   - menuID: Unique identifier (e.g., "spell_menu", "inventory")
    ///   - builder: Closure that builds the specialized view
    func register(_ menuID: String, builder: @escaping ViewBuilder) {
        specializations[menuID] = builder
        print("[MenuRouter] Registered specialization for '\(menuID)'")
    }

    /// Unregister a specialization
    func unregister(_ menuID: String) {
        specializations.removeValue(forKey: menuID)
    }

    /// Check if a menu ID has a specialization
    func hasSpecialization(for menuID: String) -> Bool {
        specializations[menuID] != nil
    }

    // MARK: - Default Registrations

    private func registerDefaultSpecializations() {
        // These will be populated when specialized sheets integrate with router
        // For now, all menus fall through to NHMenuSheet (default)
    }

    // MARK: - View Building

    /// Build the appropriate view for a context
    /// Returns specialized view if registered, otherwise NHMenuSheet
    func view(for context: NHMenuContext, onSelect: @escaping SelectionHandler) -> AnyView {
        if let menuID = context.menuID,
           let builder = specializations[menuID] {
            // Use specialized view
            return builder(context)
        }
        // Use default generic menu
        return AnyView(NHMenuSheet(context: context, onSelect: onSelect))
    }

    // MARK: - Menu Presentation

    /// Show a menu with the given context
    func showMenu(_ context: NHMenuContext, completion: @escaping SelectionHandler) {
        activeContext = context
        currentCompletion = completion
        isShowingMenu = true

        // UX Spec: .light haptic on menu present
        HapticManager.shared.tap()

        print("[MenuRouter] Showing menu: '\(context.prompt)' (pickMode: \(context.pickMode), items: \(context.itemCount))")
    }

    /// Dismiss current menu without selection
    func dismissMenu() {
        isShowingMenu = false
        currentCompletion?([])
        currentCompletion = nil
        activeContext = nil
        print("[MenuRouter] Menu dismissed")
    }

    /// Complete menu with selections
    func completeMenu(with selections: [NHMenuSelection]) {
        isShowingMenu = false
        currentCompletion?(selections)
        currentCompletion = nil
        activeContext = nil
        print("[MenuRouter] Menu completed with \(selections.count) selection(s)")
    }

    // MARK: - Convenience

    /// Show a simple PICK_ONE menu
    func selectOne(
        prompt: String,
        items: [NHMenuItem],
        icon: String? = nil,
        completion: @escaping (NHMenuSelection?) -> Void
    ) {
        let context = NHMenuContext.selectOne(prompt: prompt, items: items, icon: icon)
        showMenu(context) { selections in
            completion(selections.first)
        }
    }

    /// Show a PICK_ANY menu
    func selectAny(
        prompt: String,
        items: [NHMenuItem],
        icon: String? = nil,
        completion: @escaping ([NHMenuSelection]) -> Void
    ) {
        let context = NHMenuContext.selectAny(prompt: prompt, items: items, icon: icon)
        showMenu(context, completion: completion)
    }

    /// Show a PICK_NONE display
    func display(
        title: String,
        items: [NHMenuItem],
        icon: String? = nil
    ) {
        let context = NHMenuContext(
            prompt: title,
            pickMode: .none,
            items: items,
            icon: icon
        )
        showMenu(context) { _ in }
    }
}
