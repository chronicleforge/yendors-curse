//
//  QuantityPickerView.swift
//  nethack
//
//  Main quantity picker UI for modern touch interaction on iPad
//

import SwiftUI

struct QuantityPickerView: View {
    @State private var viewModel: QuantityPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // Animation states
    @State private var appearAnimation = false
    @State private var bounceAnimation = false

    init(
        item: InventoryItem,
        action: NetHackAction,
        maxQuantity: Int,
        onCompletion: @escaping (Int?) -> Void
    ) {
        _viewModel = State(wrappedValue: QuantityPickerViewModel(
            item: item,
            action: action,
            maxQuantity: maxQuantity,
            onCompletion: onCompletion
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding(.horizontal, QuantityPickerTheme.adaptivePadding)
                .padding(.top, QuantityPickerTheme.largePadding)
                .padding(.bottom, QuantityPickerTheme.standardPadding)

            // Quantity Display
            quantityDisplayView
                .padding(.horizontal, QuantityPickerTheme.adaptivePadding)
                .padding(.bottom, QuantityPickerTheme.largePadding)

            // Slider Control
            sliderControlView
                .padding(.horizontal, QuantityPickerTheme.adaptivePadding)
                .padding(.bottom, QuantityPickerTheme.largePadding)

            // Preset Buttons
            presetButtonsView
                .padding(.horizontal, QuantityPickerTheme.adaptivePadding)
                .padding(.bottom, QuantityPickerTheme.largePadding)

            // Action Buttons
            actionButtonsView
                .padding(.horizontal, QuantityPickerTheme.adaptivePadding)
                .padding(.bottom, QuantityPickerTheme.largePadding)
        }
        .background(QuantityPickerTheme.backgroundColor)
        .cornerRadius(QuantityPickerTheme.sheetCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: QuantityPickerTheme.sheetCornerRadius)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(radius: 20)
        .frame(maxWidth: QuantityPickerTheme.popoverMaxWidth)
        .scaleEffect(appearAnimation ? 1.0 : 0.8)
        .opacity(appearAnimation ? 1.0 : 0)
        .onAppear {
            withAnimation(QuantityPickerTheme.standardAnimation) {
                appearAnimation = true
            }
        }
        .sheet(isPresented: $viewModel.showingDirectInput) {
            DirectInputSheet(viewModel: viewModel)
                .presentationDetents([.height(QuantityPickerTheme.directInputSheetHeight)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Item name
            Text(viewModel.itemNameString)
                .font(QuantityPickerTheme.itemNameFont)
                .foregroundColor(QuantityPickerTheme.textPrimary)
                .lineLimit(1)

            // Action subtitle
            Text(viewModel.actionSubtitle)
                .font(QuantityPickerTheme.secondaryFont)
                .foregroundColor(QuantityPickerTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Quantity Display View

    private var quantityDisplayView: some View {
        HStack {
            // Decrement button
            Button(action: viewModel.decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(
                        viewModel.selectedQuantity > 1
                            ? QuantityPickerTheme.accentColor
                            : Color.gray.opacity(0.3)
                    )
            }
            .disabled(viewModel.selectedQuantity <= 1)
            .scaleEffect(viewModel.selectedQuantity > 1 ? 1.0 : 0.9)
            .animation(QuantityPickerTheme.quickAnimation, value: viewModel.selectedQuantity)

            Spacer()

            // Quantity number
            VStack(spacing: 2) {
                Text(viewModel.quantityDisplayText)
                    .font(QuantityPickerTheme.quantityDisplayFont)
                    .foregroundColor(QuantityPickerTheme.textPrimary)
                    .scaleEffect(bounceAnimation ? 1.1 : 1.0)
                    .onChange(of: viewModel.selectedQuantity) { oldValue, newValue in
                        withAnimation(QuantityPickerTheme.quickAnimation) {
                            bounceAnimation = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(QuantityPickerTheme.quickAnimation) {
                                bounceAnimation = false
                            }
                        }
                    }

                // Max quantity indicator
                if viewModel.maxQuantity > 1 {
                    Text("of \(viewModel.maxQuantity)")
                        .font(QuantityPickerTheme.secondaryFont)
                        .foregroundColor(QuantityPickerTheme.textSecondary)
                }
            }

            Spacer()

            // Increment button
            Button(action: viewModel.increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(
                        viewModel.selectedQuantity < viewModel.maxQuantity
                            ? QuantityPickerTheme.accentColor
                            : Color.gray.opacity(0.3)
                    )
            }
            .disabled(viewModel.selectedQuantity >= viewModel.maxQuantity)
            .scaleEffect(viewModel.selectedQuantity < viewModel.maxQuantity ? 1.0 : 0.9)
            .animation(QuantityPickerTheme.quickAnimation, value: viewModel.selectedQuantity)
        }
    }

    // MARK: - Slider Control View

    private var sliderControlView: some View {
        VStack(spacing: QuantityPickerTheme.compactPadding) {
            // Slider
            Rectangle()
                .fill(Color.clear)
                .frame(height: QuantityPickerTheme.sliderThumbSize)
                .quantitySliderStyle(
                    value: $viewModel.sliderValue,
                    range: 0...1,
                    snapPoints: viewModel.sliderSnapPoints
                )

            // Direct input button
            Button(action: viewModel.openDirectInput) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                    Text("Enter Amount")
                        .font(QuantityPickerTheme.secondaryFont)
                }
                .foregroundColor(QuantityPickerTheme.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(QuantityPickerTheme.presetButtonBackground)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Preset Buttons View

    private var presetButtonsView: some View {
        HStack(spacing: QuantityPickerTheme.presetButtonSpacing) {
            ForEach(viewModel.presetQuantities, id: \.self) { preset in
                PresetButton(
                    value: preset,
                    maxValue: viewModel.maxQuantity,
                    isSelected: viewModel.isPresetSelected(preset),
                    action: { viewModel.selectPreset(preset) }
                )
            }
        }
    }

    // MARK: - Action Buttons View

    private var actionButtonsView: some View {
        HStack(spacing: QuantityPickerTheme.standardPadding) {
            // Cancel button
            Button(action: {
                withAnimation(QuantityPickerTheme.standardAnimation) {
                    appearAnimation = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.cancel()
                    dismiss()
                }
            }) {
                Text("Cancel")
                    .font(QuantityPickerTheme.actionButtonFont)
                    .foregroundColor(QuantityPickerTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                            .fill(Color.gray.opacity(0.2))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            // Confirm button
            Button(action: {
                withAnimation(QuantityPickerTheme.standardAnimation) {
                    appearAnimation = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    viewModel.confirmQuantity()
                    dismiss()
                }
            }) {
                Text(confirmButtonText)
                    .font(QuantityPickerTheme.actionButtonFont)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                            .fill(confirmButtonColor)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var confirmButtonText: String {
        switch viewModel.action.command {
        case "d": return "Drop \(viewModel.selectedQuantity)"
        case "t": return "Throw \(viewModel.selectedQuantity)"
        case "e": return "Eat \(viewModel.selectedQuantity)"
        case "q": return "Quaff \(viewModel.selectedQuantity)"
        case "r": return "Read \(viewModel.selectedQuantity)"
        default: return "Confirm \(viewModel.selectedQuantity)"
        }
    }

    private var confirmButtonColor: Color {
        switch viewModel.action.command {
        case "d", "t":
            return viewModel.selectedQuantity == viewModel.maxQuantity
                ? QuantityPickerTheme.destructiveColor
                : QuantityPickerTheme.accentColor
        default:
            return QuantityPickerTheme.accentColor
        }
    }
}

// MARK: - Preset Button Component

private struct PresetButton: View {
    let value: Int
    let maxValue: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(QuantityPickerTheme.formatQuantity(value, max: maxValue))
                .font(QuantityPickerTheme.presetButtonFont)
                .foregroundColor(isSelected ? .white : QuantityPickerTheme.textPrimary)
                .frame(minWidth: QuantityPickerTheme.presetButtonMinWidth)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                        .fill(
                            isSelected
                                ? QuantityPickerTheme.presetButtonSelectedBackground
                                : QuantityPickerTheme.presetButtonBackground
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                        .stroke(
                            isSelected
                                ? Color.clear
                                : Color.gray.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(QuantityPickerTheme.quickAnimation, value: isSelected)
    }
}

// MARK: - Direct Input Sheet

struct DirectInputSheet: View {
    @Bindable var viewModel: QuantityPickerViewModel
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: QuantityPickerTheme.largePadding) {
            // Title
            Text("Enter Quantity")
                .font(.title2.bold())
                .foregroundColor(QuantityPickerTheme.textPrimary)

            // Input field
            VStack(alignment: .leading, spacing: 8) {
                TextField("Amount", text: $viewModel.directInputText)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                viewModel.isDirectInputValid
                                    ? Color.gray.opacity(0.3)
                                    : QuantityPickerTheme.destructiveColor,
                                lineWidth: 2
                            )
                    )

                // Error message
                if let errorMessage = viewModel.inputErrorMessage {
                    Text(errorMessage)
                        .font(QuantityPickerTheme.secondaryFont)
                        .foregroundColor(QuantityPickerTheme.destructiveColor)
                }

                // Range hint
                Text("Enter a value between 1 and \(viewModel.maxQuantity)")
                    .font(QuantityPickerTheme.secondaryFont)
                    .foregroundColor(QuantityPickerTheme.textSecondary)
            }

            Spacer()

            // Action buttons
            HStack(spacing: QuantityPickerTheme.standardPadding) {
                Button("Cancel") {
                    viewModel.cancelDirectInput()
                    dismiss()
                }
                .font(QuantityPickerTheme.actionButtonFont)
                .foregroundColor(QuantityPickerTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                        .fill(Color.gray.opacity(0.2))
                )

                Button("Confirm") {
                    viewModel.confirmDirectInput()
                    if viewModel.showingDirectInput == false {
                        dismiss()
                    }
                }
                .font(QuantityPickerTheme.actionButtonFont)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                        .fill(
                            viewModel.isDirectInputValid
                                ? QuantityPickerTheme.accentColor
                                : Color.gray.opacity(0.3)
                        )
                )
                .disabled(!viewModel.isDirectInputValid || viewModel.directInputText.isEmpty)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(QuantityPickerTheme.largePadding)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}