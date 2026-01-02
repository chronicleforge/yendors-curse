import SwiftUI

// MARK: - ClassSwiper

/// A horizontal class selector with left/right arrows and swipe gestures
/// SWIFTUI-A-001: Uses spring animations with bounce 0.15 for professional feel
/// SWIFTUI-HIG-001: Minimum 44pt touch targets for accessibility
struct ClassSwiper: View {
    @Binding var selectedClassIndex: Int
    let allClasses: [ClassInfo]
    let geometry: GeometryProxy

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var isLandscape: Bool {
        geometry.size.width > geometry.size.height
    }

    private var selectedIndex: Int {
        selectedClassIndex
    }

    private var selectedClass: ClassInfo {
        allClasses[selectedClassIndex]
    }

    // MARK: - Sizing

    private var titleFontSize: CGFloat {
        guard !device.isPhone || !isLandscape else { return 22 }
        switch device {
        case .phone: return 26
        case .tabletCompact: return 30
        case .tablet: return 34
        }
    }

    private var difficultyFontSize: CGFloat {
        guard !device.isPhone || !isLandscape else { return 11 }
        return ResponsiveLayout.fontSize(.footnote, for: geometry)
    }

    private var arrowSize: CGFloat {
        guard !device.isPhone || !isLandscape else { return 16 }
        switch device {
        case .phone: return 20
        case .tabletCompact: return 22
        case .tablet: return 24
        }
    }

    private var arrowTouchWidth: CGFloat {
        // SWIFTUI-HIG-001: Minimum 44pt touch target
        max(44, arrowSize + 20)
    }

    private var swiperHeight: CGFloat {
        guard !device.isPhone || !isLandscape else { return 48 }
        switch device {
        case .phone: return 56
        case .tabletCompact: return 64
        case .tablet: return 72
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Left arrow button
            Button {
                navigatePrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: arrowSize, weight: .bold))
                    .foregroundColor(selectedIndex > 0 ? .white : .white.opacity(0.3))
                    .frame(width: arrowTouchWidth, height: swiperHeight)
                    .contentShape(Rectangle()) // SWIFTUI-M-003: Ensure full area is tappable
            }
            .disabled(selectedIndex == 0)

            Spacer()

            // Center: Class name + Difficulty
            VStack(spacing: 4) {
                Text(selectedClass.name.uppercased())
                    .font(.custom("PirataOne-Regular", size: titleFontSize))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.9), radius: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .offset(x: dragOffset)

                HStack(spacing: 6) {
                    Circle()
                        .fill(selectedClass.difficulty.color)
                        .frame(width: 8, height: 8)

                    Text(selectedClass.difficulty.rawValue)
                        .font(.system(size: difficultyFontSize, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width * 0.5 // Dampen drag
                    }
                    .onEnded { value in
                        handleSwipe(translation: value.translation.width)
                    }
            )

            Spacer()

            // Right arrow button
            Button {
                navigateNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: arrowSize, weight: .bold))
                    .foregroundColor(selectedIndex < allClasses.count - 1 ? .white : .white.opacity(0.3))
                    .frame(width: arrowTouchWidth, height: swiperHeight)
                    .contentShape(Rectangle()) // SWIFTUI-M-003: Ensure full area is tappable
            }
            .disabled(selectedIndex == allClasses.count - 1)
        }
        .frame(height: swiperHeight)
        .background(Color.nethackGray200.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: ResponsiveLayout.cornerRadius(for: geometry)))
        .overlay(
            RoundedRectangle(cornerRadius: ResponsiveLayout.cornerRadius(for: geometry))
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.nethackGray100.opacity(0.5), radius: 5, y: 3)
    }

    // MARK: - Navigation

    private func navigatePrevious() {
        guard selectedClassIndex > 0 else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
            selectedClassIndex -= 1
        }
    }

    private func navigateNext() {
        guard selectedClassIndex < allClasses.count - 1 else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
            selectedClassIndex += 1
        }
    }

    private func handleSwipe(translation: CGFloat) {
        let swipeThreshold: CGFloat = 50

        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) {
            if translation < -swipeThreshold && selectedClassIndex < allClasses.count - 1 {
                selectedClassIndex += 1
            } else if translation > swipeThreshold && selectedClassIndex > 0 {
                selectedClassIndex -= 1
            }
            dragOffset = 0
        }
    }
}

// MARK: - PickerRow

/// A horizontal row of three pickers: Race, Gender, Alignment
/// Uses ResponsiveSwipePicker for consistent styling
struct PickerRow: View {
    @Binding var selectedRaceIndex: Int
    @Binding var selectedGenderIndex: Int
    @Binding var selectedAlignmentIndex: Int
    let availableRaces: [String]
    var availableGenders: [String] = ["Male", "Female"]  // NetHack has fixed genders
    let availableAlignments: [String]
    let geometry: GeometryProxy

    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }

    private var isLandscape: Bool {
        geometry.size.width > geometry.size.height
    }

    private var spacing: CGFloat {
        guard !device.isPhone || !isLandscape else { return 8 }
        return ResponsiveLayout.spacing(.medium, for: geometry)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ResponsiveSwipePicker(
                label: "Race",
                selectedIndex: $selectedRaceIndex,
                options: availableRaces,
                geometry: geometry
            )

            ResponsiveSwipePicker(
                label: "Gender",
                selectedIndex: $selectedGenderIndex,
                options: availableGenders,
                geometry: geometry
            )

            ResponsiveSwipePicker(
                label: "Align",
                selectedIndex: $selectedAlignmentIndex,
                options: availableAlignments,
                geometry: geometry
            )
        }
    }
}

// MARK: - Previews

#Preview("Class Swiper - Phone Portrait") {
    GeometryReader { geometry in
        VStack(spacing: 20) {
            ClassSwiperPreviewWrapper(geometry: geometry)
        }
        .padding()
        .background(Color(red: 50/255, green: 48/255, blue: 47/255))
    }
    .frame(width: 390, height: 300)
    .preferredColorScheme(.dark)
}

#Preview("Picker Row - Phone Portrait") {
    GeometryReader { geometry in
        VStack(spacing: 20) {
            PickerRowPreviewWrapper(geometry: geometry)
        }
        .padding()
        .background(Color(red: 50/255, green: 48/255, blue: 47/255))
    }
    .frame(width: 390, height: 200)
    .preferredColorScheme(.dark)
}

#Preview("Full Section - Tablet") {
    GeometryReader { geometry in
        VStack(spacing: 20) {
            ClassSwiperPreviewWrapper(geometry: geometry)
            PickerRowPreviewWrapper(geometry: geometry)
        }
        .padding()
        .background(Color(red: 50/255, green: 48/255, blue: 47/255))
    }
    .frame(width: 800, height: 300)
    .preferredColorScheme(.dark)
}

// MARK: - Preview Helpers

private struct ClassSwiperPreviewWrapper: View {
    let geometry: GeometryProxy
    @State private var selectedClassIndex = 0

    var body: some View {
        ClassSwiper(
            selectedClassIndex: $selectedClassIndex,
            allClasses: ClassDataProvider.allClasses,
            geometry: geometry
        )
    }
}

private struct PickerRowPreviewWrapper: View {
    let geometry: GeometryProxy
    @State private var raceIndex = 0
    @State private var genderIndex = 0
    @State private var alignmentIndex = 0

    var body: some View {
        PickerRow(
            selectedRaceIndex: $raceIndex,
            selectedGenderIndex: $genderIndex,
            selectedAlignmentIndex: $alignmentIndex,
            availableRaces: ["Human", "Dwarf", "Elf", "Gnome", "Orc"],
            availableGenders: ["Male", "Female"],
            availableAlignments: ["Lawful", "Neutral", "Chaotic"],
            geometry: geometry
        )
    }
}
