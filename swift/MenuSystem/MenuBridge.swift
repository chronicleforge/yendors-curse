import Foundation
import SwiftUI
import Combine

// MARK: - Constants (must match RealNetHackBridge.h)

private let IOS_PICK_NONE: Int32 = 0
private let IOS_PICK_ONE: Int32 = 1
private let IOS_PICK_ANY: Int32 = 2
private let IOS_MAX_MENU_ITEMS = 256
private let IOS_MAX_MENU_TEXT = 256

// MARK: - C Struct Offsets (from struct_size_test)

// IOSMenuItem (276 bytes total)
private let MENUITEM_SELECTOR_OFFSET = 0
private let MENUITEM_GLYPH_OFFSET = 4
private let MENUITEM_TEXT_OFFSET = 8
private let MENUITEM_ATTRIBUTES_OFFSET = 264
private let MENUITEM_IDENTIFIER_OFFSET = 268
private let MENUITEM_ITEMFLAGS_OFFSET = 272
private let MENUITEM_SIZE = 276

// IOSMenuContext
private let CONTEXT_HOW_OFFSET = 0
private let CONTEXT_PROMPT_OFFSET = 4
private let CONTEXT_ITEMCOUNT_OFFSET = 260
private let CONTEXT_WINDOWID_OFFSET = 264
private let CONTEXT_ITEMS_OFFSET = 268

// MARK: - C Type Mirror for Selection Result

/// Mirror of IOSMenuSelection from RealNetHackBridge.h
public struct CMenuSelection {
    public var item_index: Int32
    public var count: Int32
    
    public init(item_index: Int32, count: Int32) {
        self.item_index = item_index
        self.count = count
    }
}

// MARK: - C Function Imports

/// Register menu callback with C bridge
/// The callback signature: (context*, selections*, max_selections) -> num_selections
@_silgen_name("ios_register_menu_callback")
private func _ios_register_menu_callback(
    _ callback: @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, Int32) -> Int32
)

/// Unregister menu callback
@_silgen_name("ios_unregister_menu_callback")
private func _ios_unregister_menu_callback()

/// Check if menu callback is registered
@_silgen_name("ios_has_menu_callback")
private func _ios_has_menu_callback() -> Bool

// MARK: - Menu Bridge Singleton

/// Bridge between C menu system and Swift MenuRouter
/// Handles synchronous callback from C game thread by blocking until UI responds
final class MenuBridge: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MenuBridge()
    
    // MARK: - State

    /// Semaphore for blocking C thread until UI responds
    private let responseSemaphore = DispatchSemaphore(value: 0)

    /// Result from UI selection (protected by semaphore)
    private var pendingSelections: [CMenuSelection] = []
    private var selectionCount: Int32 = 0

    /// Lock for thread-safe access to pending state
    private let stateLock = NSLock()

    /// Flag to track if we're waiting for UI response (prevents stale signals)
    private var isWaitingForResponse = false
    
    /// Whether bridge is active
    @Published private(set) var isActive = false
    
    /// Current menu being displayed (for debugging)
    @Published var currentPrompt: String = ""
    
    // MARK: - Init
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register the menu callback with C bridge
    /// Call this after NetHack is initialized
    func activate() {
        guard !isActive else {
            print("[MenuBridge] Already active")
            return
        }
        
        // Register our global callback function
        _ios_register_menu_callback(menuCallbackTrampoline)
        isActive = true
        print("[MenuBridge] Menu bridge activated - callback registered")
    }
    
    /// Deactivate and unregister callback
    func deactivate() {
        guard isActive else { return }
        
        _ios_unregister_menu_callback()
        isActive = false
        print("[MenuBridge] Menu bridge deactivated")
    }
    
    // MARK: - Internal: Handle C Callback

    /// Called from the C callback trampoline
    /// Runs on NetHack game thread - must dispatch to main for UI
    func handleMenuRequest(
        contextPtr: UnsafeRawPointer,
        selectionsPtr: UnsafeMutableRawPointer,
        maxSelections: Int32
    ) -> Int32 {

        // Parse the C context
        let context = parseContext(contextPtr)

        print("[MenuBridge] ====== MENU REQUEST ======")
        print("[MenuBridge] Received menu: '\(context.prompt)' with \(context.itemCount) items, mode=\(context.pickMode)")
        print("[MenuBridge] Thread: \(Thread.isMainThread ? "MAIN" : "GAME")")

        #if DEBUG
        // Structured log for Loki/Grafana
        let escapedPrompt = context.prompt.replacingOccurrences(of: "\"", with: "\\\"")
        print("{\"cat\":\"MENU\",\"evt\":\"menu_request_received\",\"prompt\":\"\(escapedPrompt)\",\"items\":\(context.itemCount),\"mode\":\(context.pickMode.rawValue)}")
        #endif

        // Log ALL items for debugging loot flow
        for (i, item) in context.items.enumerated() {
            print("[MenuBridge]   Item \(i): selector='\(item.selector ?? Character("-"))' text='\(item.text.prefix(60))'")
        }

        // Log selectors for loot detection debugging
        let allSelectors = context.items.compactMap { $0.selector }
        print("[MenuBridge] All selectors: \(allSelectors)")

        // If no items, return cancel
        guard context.itemCount > 0 else {
            print("[MenuBridge] Empty menu - returning cancel")
            return 0
        }

        // DEBUG: Check pending mode status BEFORE trying auto-selection
        let hasPendingMode = PendingLootModeStorage.shared.hasPending()
        print("[MenuBridge] DEBUG: hasPendingMode=\(hasPendingMode)")

        // Check for loot options menu auto-selection (native mode)
        // Loot options menu has items with selectors: o, i, b, r, s, :, n, q
        if let autoSelection = tryLootOptionsAutoSelection(context: context) {
            print("[MenuBridge] Auto-selected loot option: index=\(autoSelection.item_index)")
            let destPtr = selectionsPtr.assumingMemoryBound(to: CMenuSelection.self)
            destPtr[0] = autoSelection
            return 1
        }

        // Check for category selection menu auto-selection (after put-in was selected)
        if let categorySelections = tryCategoryAutoSelection(context: context, maxSelections: maxSelections) {
            print("[MenuBridge] Auto-selected \(categorySelections.count) categories")
            let destPtr = selectionsPtr.assumingMemoryBound(to: CMenuSelection.self)
            for (i, sel) in categorySelections.enumerated() {
                destPtr[i] = sel
            }
            return Int32(categorySelections.count)
        }

        // Reset pending state (thread-safe)
        stateLock.lock()
        pendingSelections = []
        selectionCount = 0
        isWaitingForResponse = true
        stateLock.unlock()

        // Consume any stale signal from previous timeout
        // (non-blocking check - if signal was left over, consume it)
        _ = responseSemaphore.wait(timeout: .now())

        // Dispatch to main thread to show UI
        DispatchQueue.main.async { [weak self] in
            self?.showMenuOnMainThread(context: context)
        }

        // Block until UI responds (semaphore is signaled)
        // SAFETY: Timeout after 60 seconds to prevent permanent freeze
        print("[MenuBridge] Blocking game thread, waiting for UI response (60s timeout)...")
        let waitResult = responseSemaphore.wait(timeout: .now() + 60)

        // Clear waiting flag
        stateLock.lock()
        isWaitingForResponse = false
        stateLock.unlock()

        if waitResult == .timedOut {
            print("[MenuBridge] ⚠️ TIMEOUT: Menu UI did not respond within 60 seconds - returning cancel")
            // Dismiss any stuck menu on main thread (with proper actor isolation)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    MenuRouter.shared.dismissMenu()
                }
            }
            return 0  // Cancel - no selections
        }

        // Copy results to C buffer (thread-safe read)
        stateLock.lock()
        let count = selectionCount
        let selections = pendingSelections
        stateLock.unlock()

        print("[MenuBridge] UI responded with \(count) selection(s)")

        #if DEBUG
        // Structured log for Loki/Grafana
        print("{\"cat\":\"MENU\",\"evt\":\"menu_selection_returned\",\"count\":\(count)}")
        #endif

        if count > 0 {
            let destPtr = selectionsPtr.assumingMemoryBound(to: CMenuSelection.self)
            for i in 0..<Int(min(count, maxSelections)) {
                destPtr[i] = selections[i]
            }
        }

        return count
    }

    /// Try to auto-select a loot option if we have a pending mode from LootOptionsPicker
    /// Returns a selection if auto-selection is possible, nil otherwise
    private func tryLootOptionsAutoSelection(context: NHMenuContext) -> CMenuSelection? {
        // Only PICK_ONE menus with typical loot options
        guard context.pickMode == .one else {
            print("[MenuBridge] tryLoot: Not PICK_ONE (mode=\(context.pickMode))")
            return nil
        }

        // Check if this looks like a loot options menu by checking for typical selectors
        // Support both normal (o,i,b,r,s) and lootabc mode (a,b,c,d,e)
        let lootSelectors: Set<Character> = ["o", "i", "b", "r", "s", ":", "n", "q"]
        let abcSelectors: Set<Character> = ["a", "b", "c", "d", "e", ":", "n", "q"]
        let menuSelectors = Set(context.items.compactMap { $0.selector })

        print("[MenuBridge] tryLoot: menuSelectors=\(menuSelectors)")

        // Must have at least o, i, or b (normal) OR a, b, c (abc mode) to be a loot menu
        let hasNormalLoot = menuSelectors.contains("o") || menuSelectors.contains("i")
        let hasAbcLoot = menuSelectors.contains("a") && menuSelectors.contains("c") && menuSelectors.contains("d")
        guard hasNormalLoot || menuSelectors.contains("b") || hasAbcLoot else {
            print("[MenuBridge] tryLoot: Not a loot menu (no o/i/b or a/c/d)")
            return nil
        }

        // Check if most selectors match loot options
        let matchCount = max(
            menuSelectors.intersection(lootSelectors).count,
            menuSelectors.intersection(abcSelectors).count
        )
        guard matchCount >= 3 else {
            print("[MenuBridge] tryLoot: Not enough matches (matchCount=\(matchCount))")
            return nil
        }

        print("[MenuBridge] Detected loot options menu (matched \(matchCount) selectors)")

        // Check for pending loot mode (thread-safe access via PendingLootModeStorage)
        guard let mode = PendingLootModeStorage.shared.consume() else {
            print("[MenuBridge] No pending loot mode - showing menu UI")
            return nil
        }

        // Find the item - try selector first, then text matching
        // Text matching handles lootabc mode where selectors are a,b,c,d,e instead of o,i,b,r,s
        let targetSelector = mode.character
        var itemIndex = context.items.firstIndex(where: { $0.selector == targetSelector })

        // If not found by selector, try matching by text content
        if itemIndex == nil {
            let textPatterns: [LootMode: String] = [
                .takeOut: "take",
                .putIn: "put",
                .both: "both",
                .reversed: "reversed",
                .stash: "stash",
                .look: "look"
            ]
            if let pattern = textPatterns[mode] {
                itemIndex = context.items.firstIndex(where: {
                    $0.text.lowercased().contains(pattern)
                })
                if itemIndex != nil {
                    print("[MenuBridge] Found by text match: '\(pattern)'")
                }
            }
        }

        guard let index = itemIndex else {
            print("[MenuBridge] WARNING: Pending mode '\(mode.rawValue)' not found in menu options")
            return nil
        }

        print("[MenuBridge] Auto-selecting '\(mode.displayName)' (selector: '\(targetSelector)', index: \(index))")
        return CMenuSelection(item_index: Int32(index), count: 1)
    }

    /// Try to auto-select all categories when we're in put-in mode
    /// Returns selections for all selectable items, nil if not applicable
    private func tryCategoryAutoSelection(context: NHMenuContext, maxSelections: Int32) -> [CMenuSelection]? {
        // Only PICK_ANY menus (multi-select for categories)
        guard context.pickMode == .any else { return nil }

        // Check if we're expecting a category selection
        guard PendingLootModeStorage.shared.consumeExpectCategorySelection() else {
            return nil
        }

        // This is the category selection menu - auto-select all selectable items
        print("[MenuBridge] Detected category selection menu - auto-selecting all categories")

        var selections: [CMenuSelection] = []

        for (index, item) in context.items.enumerated() {
            // Skip headers (no selector) and special items
            guard item.selector != nil else { continue }

            // Skip "nothing" or "quit" type options
            let text = item.text.lowercased()
            if text.contains("nothing") || text.contains("quit") || text.contains("cancel") {
                continue
            }

            // Select this category
            selections.append(CMenuSelection(item_index: Int32(index), count: 1))
            print("[MenuBridge]   Selected category: '\(item.text)'")

            if selections.count >= Int(maxSelections) {
                break
            }
        }

        // If we found selectable items, return them
        guard !selections.isEmpty else {
            print("[MenuBridge] No selectable categories found")
            return nil
        }

        return selections
    }

    /// Show menu UI on main thread
    private func showMenuOnMainThread(context: NHMenuContext) {
        // Must run on main thread
        assert(Thread.isMainThread, "showMenuOnMainThread must be called on main thread")

        currentPrompt = context.prompt

        // Use MenuRouter to show the menu
        // CRITICAL: MenuRouter is @MainActor, so we must use assumeIsolated
        // since we're calling from non-actor context (even though we're on main thread)
        print("[MenuBridge] Calling MenuRouter.showMenu on main thread (assumeIsolated)")
        MainActor.assumeIsolated {
            MenuRouter.shared.showMenu(context) { [weak self] selections in
                print("[MenuBridge] ====== MENU COMPLETION ======")
                print("[MenuBridge] Completion called with \(selections.count) selections")
                guard let self = self else { return }

                // Convert NHMenuSelection to CMenuSelection
                let cSelections: [CMenuSelection] = selections.enumerated().compactMap { _, sel in
                    // Find the item index by matching the item ID
                    guard let itemIndex = context.items.firstIndex(where: { $0.id == sel.item.id }) else {
                        print("[MenuBridge] WARNING: Could not find item index for selection")
                        return nil
                    }
                    return CMenuSelection(
                        item_index: Int32(itemIndex),
                        count: Int32(sel.count)
                    )
                }

                // Store results (thread-safe)
                self.stateLock.lock()
                let shouldSignal = self.isWaitingForResponse
                if shouldSignal {
                    self.pendingSelections = cSelections
                    self.selectionCount = Int32(cSelections.count)
                }
                self.stateLock.unlock()

                print("[MenuBridge] User selected \(cSelections.count) item(s)")

                // Only signal if we're still waiting (prevents stale signal after timeout)
                if shouldSignal {
                    self.responseSemaphore.signal()
                } else {
                    print("[MenuBridge] Late response ignored (timeout already occurred)")
                }
            }
        }
    }
    
    // MARK: - Parsing
    
    /// Parse IOSMenuContext from C pointer into Swift NHMenuContext
    private func parseContext(_ ptr: UnsafeRawPointer) -> NHMenuContext {
        // Read header fields using known offsets
        let how = ptr.load(fromByteOffset: CONTEXT_HOW_OFFSET, as: Int32.self)
        
        let promptPtr = ptr.advanced(by: CONTEXT_PROMPT_OFFSET).assumingMemoryBound(to: CChar.self)
        let prompt = String(cString: promptPtr)
        
        let itemCount = Int(ptr.load(fromByteOffset: CONTEXT_ITEMCOUNT_OFFSET, as: Int32.self))
        let windowId = Int(ptr.load(fromByteOffset: CONTEXT_WINDOWID_OFFSET, as: Int32.self))
        
        print("[MenuBridge] Parsing context: how=\(how), itemCount=\(itemCount), windowId=\(windowId)")
        print("[MenuBridge] Prompt: '\(prompt)'")
        
        // Parse items
        var items: [NHMenuItem] = []
        let itemsBasePtr = ptr.advanced(by: CONTEXT_ITEMS_OFFSET)
        
        for i in 0..<min(itemCount, IOS_MAX_MENU_ITEMS) {
            let itemPtr = itemsBasePtr.advanced(by: i * MENUITEM_SIZE)
            let item = parseMenuItem(itemPtr, index: i)
            items.append(item)
        }
        
        // Determine pick mode
        let pickMode: NHPickMode
        switch how {
        case IOS_PICK_NONE: pickMode = .none
        case IOS_PICK_ONE: pickMode = .one
        case IOS_PICK_ANY: pickMode = .any
        default: pickMode = .one
        }
        
        return NHMenuContext(
            windowID: windowId,
            prompt: prompt.isEmpty ? "Menu" : prompt,
            pickMode: pickMode,
            items: items
        )
    }
    
    /// Parse single menu item from C pointer
    private func parseMenuItem(_ ptr: UnsafeRawPointer, index: Int) -> NHMenuItem {
        // Read fields using known offsets
        let selectorByte = ptr.load(fromByteOffset: MENUITEM_SELECTOR_OFFSET, as: CChar.self)
        let selector: Character? = selectorByte != 0 ? Character(UnicodeScalar(UInt8(bitPattern: selectorByte))) : nil
        
        let glyph = Int(ptr.load(fromByteOffset: MENUITEM_GLYPH_OFFSET, as: Int32.self))
        
        let textPtr = ptr.advanced(by: MENUITEM_TEXT_OFFSET).assumingMemoryBound(to: CChar.self)
        let text = String(cString: textPtr)
        
        let attributes = MenuItemAttributes(rawValue: UInt32(ptr.load(fromByteOffset: MENUITEM_ATTRIBUTES_OFFSET, as: Int32.self)))
        
        // identifier and itemflags available but not used in Swift model currently
        // let identifier = ptr.load(fromByteOffset: MENUITEM_IDENTIFIER_OFFSET, as: Int32.self)
        // let itemflags = ptr.load(fromByteOffset: MENUITEM_ITEMFLAGS_OFFSET, as: UInt32.self)
        
        return NHMenuItem(
            id: "\(index)",
            selector: selector,
            glyph: glyph != 0 ? glyph : nil,
            text: text,
            attributes: attributes
        )
    }
}

// MARK: - C Callback Trampoline

/// Global callback function that C can call
/// This must be a @convention(c) function, not a closure
private func menuCallbackTrampoline(
    contextPtr: UnsafeRawPointer?,
    selectionsPtr: UnsafeMutableRawPointer?,
    maxSelections: Int32
) -> Int32 {
    print("[MenuBridge] C callback trampoline invoked")
    
    guard let contextPtr = contextPtr, let selectionsPtr = selectionsPtr else {
        print("[MenuBridge] ERROR: NULL pointers in callback")
        return -1  // Error - use fallback
    }
    
    // Delegate to singleton
    return MenuBridge.shared.handleMenuRequest(
        contextPtr: contextPtr,
        selectionsPtr: selectionsPtr,
        maxSelections: maxSelections
    )
}
