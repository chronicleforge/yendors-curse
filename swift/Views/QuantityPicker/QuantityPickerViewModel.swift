//
//  QuantityPickerViewModel.swift
//  nethack
//
//  ViewModel for quantity picker - handles state and business logic
//

import SwiftUI
import Combine

@MainActor
@Observable
final class QuantityPickerViewModel {
    // MARK: - Published Properties

    /// Backing storage to prevent infinite loops
    private var _selectedQuantity: Int = 1
    private var _sliderValue: Double = 0.0

    /// Current selected quantity (clamped and validated)
    var selectedQuantity: Int {
        get { _selectedQuantity }
        set {
            let clamped = min(max(1, newValue), maxQuantity)
            guard clamped != _selectedQuantity else { return }

            _selectedQuantity = clamped
            _sliderValue = quantityToSliderValue(clamped)
            provideHapticFeedback(.selection)
        }
    }

    /// Slider value (0.0 to 1.0)
    var sliderValue: Double {
        get { _sliderValue }
        set {
            _sliderValue = newValue
            let newQuantity = sliderValueToQuantity(newValue)
            guard newQuantity != _selectedQuantity else { return }

            _selectedQuantity = min(max(1, newQuantity), maxQuantity)
        }
    }

    /// Whether direct input sheet is shown
    var showingDirectInput: Bool = false

    /// Text input for direct quantity entry
    var directInputText: String = "" {
        didSet {
            // Validate input as it's typed
            validateDirectInput()
        }
    }

    /// Whether the input is valid
    var isDirectInputValid: Bool = true

    /// Error message for invalid input
    var inputErrorMessage: String?

    // MARK: - Configuration

    /// The item being configured
    let item: InventoryItem

    /// The action to perform
    let action: NetHackAction

    /// Maximum quantity available
    let maxQuantity: Int

    /// Preset quantities for quick selection
    private(set) var presetQuantities: [Int] = []

    /// Completion handler
    let onCompletion: (Int?) -> Void

    /// Item name as Swift String (converted from C string)
    var itemNameString: String {
        guard let namePtr = item.name else { return "Unknown Item" }
        return String(cString: namePtr)
    }

    // MARK: - Private Properties

    private var hapticGenerator: UIImpactFeedbackGenerator?
    private var notificationGenerator: UINotificationFeedbackGenerator?

    // MARK: - Initialization

    init(
        item: InventoryItem,
        action: NetHackAction,
        maxQuantity: Int,
        onCompletion: @escaping (Int?) -> Void
    ) {
        self.item = item
        self.action = action
        self.maxQuantity = max(1, maxQuantity)
        self.onCompletion = onCompletion

        // Calculate preset quantities
        self.presetQuantities = QuantityPickerTheme.calculatePresets(for: self.maxQuantity)

        // Set initial quantity based on action (use backing storage to avoid triggering setters)
        let initialQuantity = calculateInitialQuantity()
        self._selectedQuantity = initialQuantity
        self._sliderValue = quantityToSliderValue(initialQuantity)

        // Prepare haptic generators
        setupHapticGenerators()
    }

    // MARK: - Public Methods

    /// Select a preset quantity
    func selectPreset(_ quantity: Int) {
        print("[QuantityPicker] selectPreset called with: \(quantity)")
        selectedQuantity = quantity
        print("[QuantityPicker] After setting selectedQuantity: \(selectedQuantity), backing: \(_selectedQuantity)")
        sliderValue = quantityToSliderValue(quantity)
        provideHapticFeedback(.impact(QuantityPickerTheme.buttonImpactStyle))
    }

    /// Open direct input sheet
    func openDirectInput() {
        directInputText = "\(selectedQuantity)"
        isDirectInputValid = true
        inputErrorMessage = nil
        showingDirectInput = true
        provideHapticFeedback(.impact(QuantityPickerTheme.buttonImpactStyle))
    }

    /// Confirm direct input
    func confirmDirectInput() {
        guard let quantity = Int(directInputText),
              quantity >= 1 && quantity <= maxQuantity else {
            isDirectInputValid = false
            inputErrorMessage = "Enter a number between 1 and \(maxQuantity)"
            provideHapticFeedback(.notification(.error))
            return
        }

        selectedQuantity = quantity
        sliderValue = quantityToSliderValue(quantity)
        showingDirectInput = false
        provideHapticFeedback(.notification(.success))
    }

    /// Cancel direct input
    func cancelDirectInput() {
        showingDirectInput = false
        directInputText = ""
        inputErrorMessage = nil
    }

    /// Confirm the selected quantity
    func confirmQuantity() {
        print("[QuantityPicker] confirmQuantity called:")
        print("  - selectedQuantity: \(selectedQuantity)")
        print("  - _selectedQuantity: \(_selectedQuantity)")
        print("  - maxQuantity: \(maxQuantity)")
        provideHapticFeedback(.impact(QuantityPickerTheme.confirmationImpactStyle))
        onCompletion(selectedQuantity)
    }

    /// Cancel the picker
    func cancel() {
        provideHapticFeedback(.impact(QuantityPickerTheme.buttonImpactStyle))
        onCompletion(nil)
    }

    /// Increment quantity by 1
    func increment() {
        if selectedQuantity < maxQuantity {
            selectedQuantity += 1
            sliderValue = quantityToSliderValue(selectedQuantity)
        }
    }

    /// Decrement quantity by 1
    func decrement() {
        if selectedQuantity > 1 {
            selectedQuantity -= 1
            sliderValue = quantityToSliderValue(selectedQuantity)
        }
    }

    /// Check if a preset is currently selected
    func isPresetSelected(_ preset: Int) -> Bool {
        selectedQuantity == preset
    }

    /// Get display text for the current quantity
    var quantityDisplayText: String {
        if selectedQuantity == maxQuantity && maxQuantity > QuantityPickerTheme.showAllButtonThreshold {
            return "All (\(maxQuantity))"
        }
        return "\(selectedQuantity)"
    }

    /// Get subtitle text based on action
    var actionSubtitle: String {
        switch action.command {
        case "d":
            return selectedQuantity == 1 ? "Drop 1 item" : "Drop \(selectedQuantity) items"
        case "t":
            return selectedQuantity == 1 ? "Throw 1 item" : "Throw \(selectedQuantity) items"
        case "e":
            return selectedQuantity == 1 ? "Eat 1 item" : "Eat \(selectedQuantity) items"
        case "q":
            return selectedQuantity == 1 ? "Quaff 1 potion" : "Quaff \(selectedQuantity) potions"
        case "r":
            return selectedQuantity == 1 ? "Read 1 scroll" : "Read \(selectedQuantity) scrolls"
        default:
            return selectedQuantity == 1 ? "Use 1 item" : "Use \(selectedQuantity) items"
        }
    }

    // MARK: - Private Methods

    private func calculateInitialQuantity() -> Int {
        // For destructive actions, default to 1
        if action.command == "d" || action.command == "t" {
            return 1
        }

        // For consumables, default to 1
        if action.command == "e" || action.command == "q" || action.command == "r" {
            return 1
        }

        // Default to half for other actions
        return max(1, maxQuantity / 2)
    }

    private func quantityToSliderValue(_ quantity: Int) -> Double {
        guard maxQuantity > 1 else { return 0.0 }
        return Double(quantity - 1) / Double(maxQuantity - 1)
    }

    private func sliderValueToQuantity(_ value: Double) -> Int {
        guard maxQuantity > 1 else { return 1 }

        let quantity = 1 + Int(round(value * Double(maxQuantity - 1)))
        return min(max(1, quantity), maxQuantity)
    }

    private func validateDirectInput() {
        // Allow empty input during typing
        if directInputText.isEmpty {
            isDirectInputValid = true
            inputErrorMessage = nil
            return
        }

        // Check if it's a valid number
        guard let quantity = Int(directInputText) else {
            isDirectInputValid = false
            inputErrorMessage = "Please enter a valid number"
            return
        }

        // Check range
        if quantity < 1 || quantity > maxQuantity {
            isDirectInputValid = false
            inputErrorMessage = "Enter a number between 1 and \(maxQuantity)"
            return
        }

        isDirectInputValid = true
        inputErrorMessage = nil
    }

    private func setupHapticGenerators() {
        hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
        hapticGenerator?.prepare()

        notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator?.prepare()
    }

    private func provideHapticFeedback(_ type: HapticFeedbackType) {
        switch type {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .impact(let style):
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case .notification(let type):
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }
    }
}

// MARK: - Supporting Types

private enum HapticFeedbackType {
    case selection
    case impact(UIImpactFeedbackGenerator.FeedbackStyle)
    case notification(UINotificationFeedbackGenerator.FeedbackType)
}

// MARK: - Slider Snap Points

extension QuantityPickerViewModel {
    /// Calculate snap points for the slider
    var sliderSnapPoints: [Double] {
        // For small quantities, snap to each value
        if maxQuantity <= 10 {
            return (1...maxQuantity).map { quantityToSliderValue($0) }
        }

        // For larger quantities, snap to presets and some intermediate points
        var snapPoints: [Double] = []

        // Add preset snap points
        for preset in presetQuantities {
            snapPoints.append(quantityToSliderValue(preset))
        }

        // Add intermediate points (every 10% of max)
        for i in stride(from: 0.0, through: 1.0, by: 0.1) {
            snapPoints.append(i)
        }

        // Remove duplicates and sort
        return Array(Set(snapPoints)).sorted()
    }

    /// Find nearest snap point for a slider value
    func nearestSnapPoint(for value: Double) -> Double {
        let snapPoints = sliderSnapPoints
        guard !snapPoints.isEmpty else { return value }

        let nearest = snapPoints.min { abs($0 - value) < abs($1 - value) }
        return nearest ?? value
    }

    /// Check if slider should snap (within threshold)
    func shouldSnap(value: Double, threshold: Double = 0.05) -> (Bool, Double) {
        let nearest = nearestSnapPoint(for: value)
        let shouldSnap = abs(value - nearest) < threshold
        return (shouldSnap, nearest)
    }
}