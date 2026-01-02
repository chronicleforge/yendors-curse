//
//  ClassTipsBox.swift
//  nethack
//
//  Shows tips and description for the currently selected class.
//  RESPONSIVE DESIGN: Works on ALL devices using ResponsiveLayout
//

import SwiftUI

/// A tips box showing class description, highlights, and recommended races
/// Ref: SWIFTUI-L-002 - Proper VStack structure with ScrollView for long content
struct ClassTipsBox: View {
    let classInfo: ClassInfo
    let geometry: GeometryProxy
    
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    // MARK: - Device Detection
    
    private var device: DeviceCategory {
        DeviceCategory.detect(for: geometry)
    }
    
    private var isLandscape: Bool {
        geometry.size.width > geometry.size.height
    }
    
    // MARK: - Computed Sizes (Device-Aware)
    
    private var headerFontSize: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 10
        }
        return ResponsiveLayout.fontSize(.footnote, for: geometry)
    }
    
    private var bodyFontSize: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 13
        }
        return ResponsiveLayout.fontSize(.body, for: geometry)
    }
    
    private var captionFontSize: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 11
        }
        return ResponsiveLayout.fontSize(.caption, for: geometry)
    }
    
    private var cardPadding: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 10
        }
        return ResponsiveLayout.cardPadding(for: geometry)
    }
    
    private var cornerRadius: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 10
        }
        return ResponsiveLayout.cornerRadius(for: geometry)
    }
    
    private var spacing: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 6
        }
        return ResponsiveLayout.spacing(.small, for: geometry)
    }
    
    private var checkmarkSize: CGFloat {
        guard !device.isPhone || !isLandscape else {
            return 10
        }
        switch device {
        case .phone: return 12
        case .tabletCompact: return 13
        case .tablet: return 14
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: spacing) {
                // TIPS Header
                tipsHeader
                
                // Description
                descriptionSection
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Highlights with checkmarks
                highlightsSection
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Recommended races
                recommendedRacesSection
            }
            .padding(cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nethackGray200.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.nethackGray100.opacity(0.5), radius: 10, y: 5)
    }
    
    // MARK: - Section Views
    
    private var tipsHeader: some View {
        Text("TIPS")
            .font(.system(size: headerFontSize, weight: .bold))
            .foregroundColor(.white.opacity(0.5))
            .accessibilityAddTraits(.isHeader)
    }
    
    private var descriptionSection: some View {
        Text(classInfo.description)
            .font(.system(size: bodyFontSize))
            .foregroundColor(.white.opacity(0.85))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(classInfo.keyHighlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: spacing) {
                    Text("\u{2713}") // Checkmark character
                        .font(.system(size: checkmarkSize, weight: .bold))
                        .foregroundColor(.ccSecondary)
                    
                    Text(highlight)
                        .font(.system(size: captionFontSize))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var recommendedRacesSection: some View {
        HStack(spacing: 4) {
            Text("Recommended:")
                .font(.system(size: captionFontSize, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Text(classInfo.recommendedRaces.joined(separator: ", "))
                .font(.system(size: captionFontSize, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ClassTipsBox_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 50/255, green: 48/255, blue: 47/255)
                    .ignoresSafeArea()
                
                ClassTipsBox(
                    classInfo: ClassDataProvider.allClasses[0],
                    geometry: geometry
                )
                .padding()
            }
        }
        .previewDisplayName("ClassTipsBox")
    }
}
#endif
