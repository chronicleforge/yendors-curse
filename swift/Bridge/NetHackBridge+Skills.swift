//
//  NetHackBridge+Skills.swift
//  nethack
//
//  Swift bridge for NetHack skill/enhance system
//  Wraps C functions from RealNetHackBridge.h
//

import Foundation

// MARK: - Skill Bridge Service

/// Service for querying and modifying player skills
/// Wraps the C bridge API for the #enhance command
@MainActor
class SkillBridgeService {

    static let shared = SkillBridgeService()

    private init() {}

    // MARK: - Public API

    /// Get all non-restricted skills for the current character
    /// - Returns: Array of SkillInfo models
    func getAllSkills() -> [SkillInfo] {
        var cSkills = [ios_skill_info_t](repeating: ios_skill_info_t(), count: Int(IOS_NUM_SKILLS))
        var count: Int32 = 0

        let result = ios_get_all_skills(&cSkills, &count)
        guard result > 0 else {
            print("[SkillBridge] Failed to get skills or no skills available")
            return []
        }

        return (0..<Int(count)).compactMap { index in
            convertToSkillInfo(cSkills[index])
        }
    }

    /// Get count of available skill slots
    /// - Returns: Number of slots available for advancement
    func getAvailableSlots() -> Int {
        Int(ios_get_available_skill_slots())
    }

    /// Get count of skills that can be advanced right now
    /// - Returns: Number of advanceable skills
    func getAdvanceableCount() -> Int {
        Int(ios_get_advanceable_skill_count())
    }

    /// Advance a skill by spending a skill slot
    /// - Parameter skillId: The skill ID (0-37) to advance
    /// - Returns: true if advancement succeeded
    func advanceSkill(_ skillId: Int) -> Bool {
        let result = ios_advance_skill(Int32(skillId))
        if result == 1 {
            print("[SkillBridge] Successfully advanced skill \(skillId)")
            return true
        } else {
            print("[SkillBridge] Failed to advance skill \(skillId)")
            return false
        }
    }

    /// Get a specific skill by ID
    /// - Parameter skillId: The skill ID (0-37)
    /// - Returns: SkillInfo if skill exists and is not restricted
    func getSkill(id skillId: Int) -> SkillInfo? {
        var cSkill = ios_skill_info_t()
        let result = ios_get_skill_by_id(Int32(skillId), &cSkill)
        guard result == 1 else { return nil }
        return convertToSkillInfo(cSkill)
    }

    // MARK: - Private Helpers

    /// Convert C struct to Swift model
    private func convertToSkillInfo(_ cSkill: ios_skill_info_t) -> SkillInfo? {
        // Extract name from C string
        let name = withUnsafePointer(to: cSkill.name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 64) {
                String(cString: $0)
            }
        }

        guard !name.isEmpty else { return nil }

        // Convert levels
        let currentLevel = SkillLevel(rawValue: Int(cSkill.current_level)) ?? .unskilled
        let maxLevel = SkillLevel(rawValue: Int(cSkill.max_level)) ?? .basic

        return SkillInfo(
            id: Int(cSkill.skill_id),
            name: name,
            currentLevel: currentLevel,
            maxLevel: maxLevel,
            practicePoints: Int(cSkill.practice_points),
            pointsNeeded: Int(cSkill.points_needed),
            canAdvance: cSkill.can_advance == 1,
            couldAdvance: cSkill.could_advance == 1,
            isMaxed: cSkill.is_peaked == 1
        )
    }
}

// MARK: - C Function Declarations

// These are declared in RealNetHackBridge.h and linked via the dylib

@_silgen_name("ios_get_available_skill_slots")
func ios_get_available_skill_slots() -> Int32

@_silgen_name("ios_get_skill_count")
func ios_get_skill_count() -> Int32

@_silgen_name("ios_get_skill_info")
func ios_get_skill_info(_ index: Int32, _ out: UnsafeMutablePointer<ios_skill_info_t>) -> Int32

@_silgen_name("ios_get_all_skills")
func ios_get_all_skills(_ out: UnsafeMutablePointer<ios_skill_info_t>, _ count: UnsafeMutablePointer<Int32>) -> Int32

@_silgen_name("ios_get_skill_by_id")
func ios_get_skill_by_id(_ skill_id: Int32, _ out: UnsafeMutablePointer<ios_skill_info_t>) -> Int32

@_silgen_name("ios_advance_skill")
func ios_advance_skill(_ skill_id: Int32) -> Int32

@_silgen_name("ios_get_advanceable_skill_count")
func ios_get_advanceable_skill_count() -> Int32

@_silgen_name("ios_get_skill_level_name")
func ios_get_skill_level_name(_ level: Int32) -> UnsafePointer<CChar>

// MARK: - C Struct Definition (mirrors RealNetHackBridge.h)

let IOS_NUM_SKILLS: Int32 = 38

struct ios_skill_info_t {
    var skill_id: Int32 = 0
    var name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    var current_level: Int32 = 0
    var max_level: Int32 = 0
    var practice_points: Int32 = 0
    var points_needed: Int32 = 0
    var can_advance: Int32 = 0
    var could_advance: Int32 = 0
    var is_peaked: Int32 = 0
    var slots_required: Int32 = 0
    var category: Int32 = 0
    var level_name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                     CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                     CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                     CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
