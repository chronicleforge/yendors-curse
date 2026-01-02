//
//  SkillEnhanceSheet.swift
//  nethack
//
//  Native SwiftUI sheet for NetHack's #enhance skill advancement system
//  Replaces the text-based menu with a touch-friendly grouped list
//
//  Design Pattern: SpellSelectionSheet + FullscreenInventoryView
//  - Glass-morphic background with .regularMaterial
//  - Grouped list by category (Weapons, Spells, Combat)
//  - Advanceable skills highlighted in gold
//  - Touch targets >= 44pt (Apple HIG)
//

import SwiftUI

// MARK: - Skill Enhance Sheet

/// Full-height sheet for skill enhancement (#enhance command)
/// Displays skills grouped by category with advancement options
struct SkillEnhanceSheet: View {
    let skills: [SkillInfo]
    let availableSlots: Int
    let onAdvance: (SkillInfo) -> Void
    let onCancel: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedCategory: SkillCategory? = nil
    @State private var advancingSkill: SkillInfo? = nil
    
    private let isPhone = ScalingEnvironment.isPhone
    
    // MARK: - Computed Properties
    
    /// Skills filtered by category and excluding restricted
    private var filteredSkills: [SkillInfo] {
        let nonRestricted = skills.filter { $0.currentLevel != .restricted }
        
        guard let category = selectedCategory else {
            return nonRestricted
        }
        
        return nonRestricted.filter { $0.category == category }
    }
    
    /// Skills grouped by category for section display
    private var groupedSkills: [(SkillCategory, [SkillInfo])] {
        let nonRestricted = skills.filter { $0.currentLevel != .restricted }
        let grouped = Dictionary(grouping: nonRestricted) { $0.category }
        
        // Return in fixed order: Weapons, Spells, Combat
        return SkillCategory.allCases.compactMap { category in
            guard let categorySkills = grouped[category], !categorySkills.isEmpty else {
                return nil
            }
            
            // Filter by selected category if set
            if let selected = selectedCategory, selected != category {
                return nil
            }
            
            return (category, categorySkills.sorted { $0.name < $1.name })
        }
    }
    
    /// Count of skills that can be advanced
    private var advanceableCount: Int {
        skills.filter { $0.canAdvance }.count
    }
    
    /// Available categories with skills
    private var availableCategories: [SkillCategory] {
        let nonRestricted = skills.filter { $0.currentLevel != .restricted }
        let categories = Set(nonRestricted.map { $0.category })
        return SkillCategory.allCases.filter { categories.contains($0) }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            if availableCategories.count > 1 {
                filterBar
            }
            
            if filteredSkills.isEmpty {
                emptyStateView
            } else {
                skillListView
            }
            
            bottomBar
        }
        .background(.regularMaterial)
        .cornerRadius(isPhone ? 12 : 16)
        .shadow(color: .black.opacity(0.3), radius: 20)
        .transition(
            reduceMotion
                ? .opacity
                : AnimationConstants.sheetAppearTransition
        )
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: isPhone ? 20 : 24))
                .foregroundColor(.gruvboxYellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Enhance Skills")
                    .font(.system(size: isPhone ? 16 : 18, weight: .bold))
                    .foregroundColor(.primary)
                
                // Skill slots available
                HStack(spacing: 4) {
                    if availableSlots > 0 {
                        Text("\(availableSlots) skill slot\(availableSlots == 1 ? "" : "s") available")
                            .font(.system(size: isPhone ? 12 : 13))
                            .foregroundColor(.gruvboxYellow)
                    } else {
                        Text("No skill slots available")
                            .font(.system(size: isPhone ? 12 : 13))
                            .foregroundColor(.nethackGray500)
                    }
                    
                    if advanceableCount > 0 {
                        Text("\(advanceableCount) can advance")
                            .font(.system(size: isPhone ? 11 : 12, weight: .medium))
                            .foregroundColor(.nethackSuccess)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.nethackSuccess.opacity(0.2))
                            )
                    }
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: isPhone ? 22 : 26))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, isPhone ? 14 : 18)
        .padding(.vertical, isPhone ? 12 : 14)
        .background(Color(.systemBackground).opacity(0.9))
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All filter
                CategoryFilterChip(
                    title: "All",
                    icon: "square.grid.2x2",
                    color: .gruvboxForeground,
                    isSelected: selectedCategory == nil,
                    count: skills.filter { $0.currentLevel != .restricted }.count
                ) {
                    withAnimation(AnimationConstants.categoryFilterSelect) {
                        selectedCategory = nil
                    }
                }
                
                // Category filters
                ForEach(availableCategories, id: \.self) { category in
                    let categorySkills = skills.filter {
                        $0.category == category && $0.currentLevel != .restricted
                    }
                    
                    CategoryFilterChip(
                        title: category.rawValue,
                        icon: category.icon,
                        color: category.color,
                        isSelected: selectedCategory == category,
                        count: categorySkills.count
                    ) {
                        withAnimation(AnimationConstants.categoryFilterSelect) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
    
    // MARK: - Skill List
    
    private var skillListView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedSkills, id: \.0) { category, categorySkills in
                    Section {
                        VStack(spacing: 4) {
                            ForEach(categorySkills) { skill in
                                SkillRowView(skill: skill) {
                                    advanceSkill(skill)
                                }
                                .id(skill.id)
                            }
                        }
                        .padding(.horizontal, isPhone ? 8 : 12)
                        .padding(.bottom, 8)
                    } header: {
                        SkillCategoryHeader(
                            category: category,
                            count: categorySkills.count,
                            advanceableCount: categorySkills.filter { $0.canAdvance }.count
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: isPhone ? 50 : 64))
                .foregroundColor(.nethackGray400)
                .emptyStateIconAnimation()
            
            Text("No Skills to Display")
                .font(.system(size: isPhone ? 16 : 18, weight: .bold))
                .foregroundColor(.nethackGray600)
            
            if selectedCategory != nil {
                Text("No \(selectedCategory!.rawValue.lowercased()) skills available")
                    .font(.system(size: isPhone ? 13 : 14))
                    .foregroundColor(.nethackGray500)
                
                Button("Show All Skills") {
                    withAnimation(AnimationConstants.categoryFilterSelect) {
                        selectedCategory = nil
                    }
                }
                .font(.system(size: isPhone ? 13 : 14, weight: .medium))
                .foregroundColor(.gruvboxYellow)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .strokeBorder(Color.gruvboxYellow.opacity(0.5), lineWidth: 1)
                )
            } else {
                Text("Practice using weapons and casting spells to improve")
                    .font(.system(size: isPhone ? 13 : 14))
                    .foregroundColor(.nethackGray500)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack {
            // Skill count
            Text("\(filteredSkills.count) skill\(filteredSkills.count == 1 ? "" : "s")")
                .font(.system(size: isPhone ? 12 : 13))
                .foregroundColor(.secondary)
            
            // Legend
            HStack(spacing: 12) {
                legendItem(symbol: "*", label: "needs XP", color: .gruvboxYellow)
                legendItem(symbol: "#", label: "maxed", color: .nethackSuccess)
            }
            .font(.system(size: isPhone ? 10 : 11))
            
            Spacer()
            
            Button(action: onCancel) {
                Text("Done")
                    .font(.system(size: isPhone ? 14 : 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, isPhone ? 20 : 28)
                    .frame(height: 44)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, isPhone ? 14 : 18)
        .padding(.vertical, isPhone ? 10 : 12)
        .background(Color(.systemBackground).opacity(0.8))
    }
    
    // MARK: - Helper Views
    
    private func legendItem(symbol: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(.system(size: isPhone ? 11 : 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .foregroundColor(.nethackGray500)
        }
    }
    
    // MARK: - Actions
    
    private func advanceSkill(_ skill: SkillInfo) {
        guard skill.canAdvance else { return }
        
        // Haptic feedback
        HapticManager.shared.success()
        
        // Visual feedback
        advancingSkill = skill
        
        // Notify parent
        onAdvance(skill)
        
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            advancingSkill = nil
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SkillEnhanceSheet_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gruvboxBackground
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                SkillEnhanceSheet(
                    skills: SkillInfo.sampleSkills,
                    availableSlots: 3,
                    onAdvance: { skill in
                        print("Advance: \(skill.name)")
                    },
                    onCancel: {
                        print("Cancelled")
                    }
                )
                .frame(maxHeight: 600)
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .previewDisplayName("Skill Enhance Sheet")
        
        // Empty state preview
        ZStack {
            Color.gruvboxBackground
                .ignoresSafeArea()
            
            SkillEnhanceSheet(
                skills: [],
                availableSlots: 0,
                onAdvance: { _ in },
                onCancel: {}
            )
            .frame(maxHeight: 400)
            .padding(.horizontal)
        }
        .previewDisplayName("Empty State")
        
        // No slots preview
        ZStack {
            Color.gruvboxBackground
                .ignoresSafeArea()
            
            SkillEnhanceSheet(
                skills: SkillInfo.sampleSkills.map { skill in
                    SkillInfo(
                        id: skill.id,
                        name: skill.name,
                        currentLevel: skill.currentLevel,
                        maxLevel: skill.maxLevel,
                        practicePoints: skill.practicePoints,
                        pointsNeeded: skill.pointsNeeded,
                        canAdvance: false,  // No slots
                        couldAdvance: skill.canAdvance,
                        isMaxed: skill.isMaxed
                    )
                },
                availableSlots: 0,
                onAdvance: { _ in },
                onCancel: {}
            )
            .frame(maxHeight: 500)
            .padding(.horizontal)
        }
        .previewDisplayName("No Slots Available")
    }
}
#endif
