//
//  SkillRowView.swift
//  nethack
//
//  Row component for displaying a single skill in the enhance sheet
//  Follows glass-morphic design pattern from FullscreenInventoryView
//

import SwiftUI

// MARK: - Skill Row View

/// A single row in the skill list showing skill name, level, and progress
struct SkillRowView: View {
    let skill: SkillInfo
    let onTap: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: isPhone ? 8 : 12) {
                // Skill name
                skillNameSection
                
                Spacer(minLength: 4)
                
                // Progress bar (only if not maxed and can progress)
                if !skill.isMaxed && skill.currentLevel != .restricted {
                    progressSection
                }
                
                // Level badge
                levelBadge
                
                // Status indicator or advance chevron
                statusSection
            }
            .padding(.horizontal, isPhone ? 10 : 14)
            .padding(.vertical, isPhone ? 10 : 12)
            .frame(minHeight: 44)  // Apple HIG minimum touch target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(rowBackground)
        .scaleEffect(isPressed ? AnimationConstants.pressScale : 1.0)
        .animation(
            reduceMotion ? nil : AnimationConstants.pressAnimation,
            value: isPressed
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .disabled(!skill.canAdvance)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(skill.canAdvance ? "Double tap to advance this skill" : "")
    }
    
    // MARK: - Subviews
    
    private var skillNameSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name.capitalized)
                .font(.system(size: isPhone ? 14 : 16, weight: .medium))
                .foregroundColor(skill.canAdvance ? .gruvboxYellow : .nethackGray800)
                .lineLimit(1)
            
            // Show max level indicator
            if skill.currentLevel < skill.maxLevel {
                Text("Max: \(skill.maxLevel.displayName)")
                    .font(.system(size: isPhone ? 10 : 11))
                    .foregroundColor(.nethackGray500)
            }
        }
    }
    
    private var progressSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.nethackGray300)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * skill.progress)
                }
            }
            .frame(width: isPhone ? 50 : 70, height: 4)
            
            // Progress text
            Text("\(skill.practicePoints)/\(skill.pointsNeeded)")
                .font(.system(size: isPhone ? 9 : 10, design: .monospaced))
                .foregroundColor(.nethackGray500)
        }
    }
    
    private var levelBadge: some View {
        Text(skill.currentLevel.shortName)
            .font(.system(size: isPhone ? 11 : 12, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, isPhone ? 6 : 8)
            .padding(.vertical, isPhone ? 3 : 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(skill.currentLevel.color)
            )
            .accessibilityLabel(skill.currentLevel.displayName)
    }
    
    private var statusSection: some View {
        Group {
            if skill.canAdvance {
                // Advance indicator
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: isPhone ? 18 : 22))
                    .foregroundColor(.gruvboxYellow)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            } else if let indicator = skill.statusIndicator {
                // Status character (* or #)
                Text(indicator)
                    .font(.system(size: isPhone ? 14 : 16, weight: .bold, design: .monospaced))
                    .foregroundColor(indicator == "#" ? .nethackSuccess : .gruvboxYellow)
                    .frame(width: isPhone ? 18 : 22)
            } else {
                // Empty spacer for alignment
                Color.clear
                    .frame(width: isPhone ? 18 : 22)
            }
        }
    }
    
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(skill.canAdvance
                  ? Color.gruvboxYellow.opacity(0.15)
                  : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        skill.canAdvance
                            ? Color.gruvboxYellow.opacity(0.4)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - Computed Properties
    
    private var progressColor: Color {
        if skill.canAdvance {
            return .gruvboxYellow
        }
        
        switch skill.progress {
        case 0..<0.33: return .nethackGray500
        case 0.33..<0.66: return .gruvboxBlue
        default: return .nethackSuccess
        }
    }
    
    private var accessibilityLabel: String {
        var label = "\(skill.name), \(skill.currentLevel.displayName)"
        
        if skill.canAdvance {
            label += ", ready to advance"
        } else if skill.isMaxed {
            label += ", at maximum"
        } else if skill.couldAdvance {
            label += ", needs more experience"
        }
        
        return label
    }
}

// MARK: - Skill Category Header

/// Section header for skill categories
struct SkillCategoryHeader: View {
    let category: SkillCategory
    let count: Int
    let advanceableCount: Int
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.system(size: isPhone ? 12 : 14, weight: .bold))
                .foregroundColor(category.color)
            
            Text(category.rawValue)
                .font(.system(size: isPhone ? 12 : 14, weight: .semibold))
                .foregroundColor(.nethackGray800)
            
            Spacer()
            
            // Show advanceable count if any
            if advanceableCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: isPhone ? 10 : 11))
                    Text("\(advanceableCount)")
                        .font(.system(size: isPhone ? 10 : 11, weight: .bold))
                }
                .foregroundColor(.gruvboxYellow)
            }
            
            Text("\(count)")
                .font(.system(size: isPhone ? 11 : 12))
                .foregroundColor(.nethackGray500)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
    }
}

// MARK: - Preview

#if DEBUG
struct SkillRowView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gruvboxBackground.ignoresSafeArea()
            
            VStack(spacing: 4) {
                SkillCategoryHeader(
                    category: .weapons,
                    count: 4,
                    advanceableCount: 1
                )
                
                ForEach(SkillInfo.sampleSkills.prefix(4)) { skill in
                    SkillRowView(skill: skill) {
                        print("Tapped: \(skill.name)")
                    }
                }
                
                SkillCategoryHeader(
                    category: .combat,
                    count: 3,
                    advanceableCount: 1
                )
                
                ForEach(SkillInfo.sampleSkills.suffix(3)) { skill in
                    SkillRowView(skill: skill) {
                        print("Tapped: \(skill.name)")
                    }
                }
            }
            .padding()
        }
        .previewDisplayName("Skill Rows")
    }
}
#endif
