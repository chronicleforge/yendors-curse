//
//  QuantitySliderStyle.swift
//  nethack
//
//  Custom slider style for quantity picker with modern touch interaction
//

import SwiftUI

struct QuantitySliderStyle: ViewModifier {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let snapPoints: [Double]
    let onValueChange: ((Double) -> Void)?

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastHapticValue: Double = 0

    private let trackHeight: CGFloat = QuantityPickerTheme.sliderTrackHeight
    private let thumbSize: CGFloat = QuantityPickerTheme.sliderThumbSize
    private let hapticThreshold: Double = 0.05

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thumbPosition = valueToPosition(value, in: width)

            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(QuantityPickerTheme.sliderTrackColor)
                    .frame(height: trackHeight)

                // Filled track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(QuantityPickerTheme.sliderFillColor)
                    .frame(width: thumbPosition + thumbSize / 2, height: trackHeight)

                // Snap point indicators
                ForEach(snapPoints, id: \.self) { snapValue in
                    let snapPosition = valueToPosition(snapValue, in: width)
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 4, height: 4)
                        .position(x: snapPosition + thumbSize / 2, y: trackHeight / 2)
                }

                // Thumb
                Circle()
                    .fill(QuantityPickerTheme.activeColor)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .frame(width: thumbSize * 0.3, height: thumbSize * 0.3)
                    )
                    .shadow(
                        color: Color.black.opacity(isDragging ? 0.3 : 0.2),
                        radius: isDragging ? 8 : 4,
                        y: isDragging ? 4 : 2
                    )
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .offset(x: thumbPosition)
                    .animation(
                        isDragging ? .none : QuantityPickerTheme.quickAnimation,
                        value: thumbPosition
                    )
            }
            .frame(height: max(trackHeight, thumbSize))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gestureValue in
                        if !isDragging {
                            isDragging = true
                            provideHapticFeedback(.impact(.light))
                        }

                        let newPosition = gestureValue.location.x - thumbSize / 2
                        let newValue = positionToValue(newPosition, in: width)
                        let clampedValue = min(max(range.lowerBound, newValue), range.upperBound)

                        // Always snap to nearest discrete point (no analog values)
                        if let nearestSnap = findNearestSnapPoint(for: clampedValue, threshold: 1.0) {
                            // Provide haptic feedback when crossing snap points
                            if abs(nearestSnap - lastHapticValue) > hapticThreshold {
                                provideHapticFeedback(.impact(.light))
                                lastHapticValue = nearestSnap
                            }
                            value = nearestSnap
                        } else {
                            // Fallback: if no snap points, clamp to range
                            value = clampedValue
                        }

                        onValueChange?(value)
                    }
                    .onEnded { _ in
                        isDragging = false

                        // Final snap to nearest point
                        if let nearestSnap = findNearestSnapPoint(for: value, threshold: 0.1) {
                            withAnimation(QuantityPickerTheme.quickAnimation) {
                                value = nearestSnap
                            }
                            provideHapticFeedback(.impact(.medium))
                        }
                    }
            )
        }
        .frame(height: max(trackHeight, thumbSize))
    }

    private func valueToPosition(_ value: Double, in width: CGFloat) -> CGFloat {
        let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(normalizedValue) * (width - thumbSize)
    }

    private func positionToValue(_ position: CGFloat, in width: CGFloat) -> Double {
        let normalizedPosition = Double(position / (width - thumbSize))
        return range.lowerBound + normalizedPosition * (range.upperBound - range.lowerBound)
    }

    private func findNearestSnapPoint(for value: Double, threshold: Double) -> Double? {
        guard !snapPoints.isEmpty else { return nil }

        let nearest = snapPoints.min { abs($0 - value) < abs($1 - value) }
        guard let nearest = nearest else { return nil }

        return abs(value - nearest) < threshold ? nearest : nil
    }

    private func provideHapticFeedback(_ type: HapticType) {
        switch type {
        case .impact(let style):
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private enum HapticType {
        case impact(UIImpactFeedbackGenerator.FeedbackStyle)
        case selection
    }
}

// MARK: - View Extension

extension View {
    func quantitySliderStyle(
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        snapPoints: [Double] = [],
        onValueChange: ((Double) -> Void)? = nil
    ) -> some View {
        self.modifier(
            QuantitySliderStyle(
                value: value,
                range: range,
                snapPoints: snapPoints,
                onValueChange: onValueChange
            )
        )
    }
}

// MARK: - Alternative Stepper Style

struct QuantityStepperView: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let onValueChange: ((Int) -> Void)?

    @State private var isDecrementPressed = false
    @State private var isIncrementPressed = false

    var body: some View {
        HStack(spacing: 0) {
            // Decrement button
            Button(action: decrement) {
                Image(systemName: "minus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(value > range.lowerBound ? QuantityPickerTheme.accentColor : Color.gray)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                            .fill(QuantityPickerTheme.presetButtonBackground)
                    )
                    .scaleEffect(isDecrementPressed ? AnimationConstants.pressScale : 1.0)
            }
            .disabled(value <= range.lowerBound)
            .onLongPressGesture(
                minimumDuration: 0.5,
                maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(QuantityPickerTheme.quickAnimation) {
                        isDecrementPressed = pressing
                    }
                },
                perform: {}
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { _ in
                        // Start rapid decrement
                        startRapidChange(increment: false)
                    }
            )

            Spacer()

            // Value display
            Text("\(value)")
                .font(QuantityPickerTheme.quantityDisplayFont)
                .foregroundColor(QuantityPickerTheme.textPrimary)
                .frame(minWidth: 80)
                .animation(.none, value: value)

            Spacer()

            // Increment button
            Button(action: increment) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(value < range.upperBound ? QuantityPickerTheme.accentColor : Color.gray)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: QuantityPickerTheme.buttonCornerRadius)
                            .fill(QuantityPickerTheme.presetButtonBackground)
                    )
                    .scaleEffect(isIncrementPressed ? AnimationConstants.pressScale : 1.0)
            }
            .disabled(value >= range.upperBound)
            .onLongPressGesture(
                minimumDuration: 0.5,
                maximumDistance: .infinity,
                pressing: { pressing in
                    withAnimation(QuantityPickerTheme.quickAnimation) {
                        isIncrementPressed = pressing
                    }
                },
                perform: {}
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onEnded { _ in
                        // Start rapid increment
                        startRapidChange(increment: true)
                    }
            )
        }
        .frame(height: 44)
    }

    private func decrement() {
        guard value > range.lowerBound else { return }
        value -= 1
        onValueChange?(value)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func increment() {
        guard value < range.upperBound else { return }
        value += 1
        onValueChange?(value)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startRapidChange(increment: Bool) {
        Task {
            var delay: UInt64 = 200_000_000 // Start with 200ms
            while increment ? (value < range.upperBound) : (value > range.lowerBound) {
                if increment {
                    self.increment()
                } else {
                    self.decrement()
                }

                try? await Task.sleep(nanoseconds: delay)

                // Speed up over time
                if delay > 50_000_000 {
                    delay = UInt64(Double(delay) * 0.9)
                }
            }
        }
    }
}