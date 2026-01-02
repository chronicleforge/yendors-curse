import Foundation
import SwiftUI

/// Represents a NetHack game message with turn-based tracking and ATR_* attributes
/// Used for turn-based opacity fading instead of time-based auto-hide
struct GameMessage: Identifiable, Codable {
    let id: UUID
    let text: String
    let turnNumber: Int
    let timestamp: Date
    var count: Int  // For smart grouping of repeated messages

    // NetHack ATR_* attributes (from wintype.h)
    let attributes: MessageAttributes

    // Category from C layer (COMBAT, DOOR, ITEM, etc.)
    let category: String

    init(text: String, turnNumber: Int, timestamp: Date = Date(),
         count: Int = 1, attributes: MessageAttributes = MessageAttributes(),
         category: String = "INFO") {
        self.id = UUID()
        self.text = text
        self.turnNumber = turnNumber
        self.timestamp = timestamp
        self.count = count
        self.attributes = attributes
        self.category = category
    }

    /// NetHack message attributes matching wintype.h definitions
    struct MessageAttributes: Codable {
        let isBold: Bool
        let isDim: Bool
        let isItalic: Bool
        let isUnderline: Bool
        let isBlink: Bool
        let isInverse: Bool
        let isUrgent: Bool
        let noHistory: Bool

        init(isBold: Bool = false, isDim: Bool = false, isItalic: Bool = false,
             isUnderline: Bool = false, isBlink: Bool = false, isInverse: Bool = false,
             isUrgent: Bool = false, noHistory: Bool = false) {
            self.isBold = isBold
            self.isDim = isDim
            self.isItalic = isItalic
            self.isUnderline = isUnderline
            self.isBlink = isBlink
            self.isInverse = isInverse
            self.isUrgent = isUrgent
            self.noHistory = noHistory
        }

        /// Create from raw NetHack ATR_* bitmask
        init(fromBitmask bitmask: Int) {
            self.isBold = (bitmask & 0x01) != 0      // ATR_BOLD
            self.isDim = (bitmask & 0x02) != 0       // ATR_DIM
            self.isItalic = (bitmask & 0x04) != 0    // ATR_ITALIC (bit 2 in flags)
            self.isUnderline = (bitmask & 0x08) != 0 // ATR_ULINE (bit 3 in flags)
            self.isBlink = (bitmask & 0x10) != 0     // ATR_BLINK (bit 4 in flags)
            self.isInverse = (bitmask & 0x80) != 0   // ATR_INVERSE (bit 7 in flags)
            self.isUrgent = (bitmask & 0x100) != 0   // ATR_URGENT (bit 8 in flags)
            self.noHistory = (bitmask & 0x200) != 0  // ATR_NOHISTORY (bit 9 in flags)
        }
    }

    /// Determines message type from attributes and text content
    var type: MessageType {
        // Urgent attribute = error
        if attributes.isUrgent {
            return .error
        }

        // Bold attribute = important/success
        if attributes.isBold {
            return .success
        }

        // Dim attribute = less important
        if attributes.isDim {
            return .ambient
        }

        // Fallback to text-based detection
        let lowercased = text.lowercased()

        // Critical/Error messages
        if lowercased.contains("die") || lowercased.contains("killed") || lowercased.contains("hits you") {
            return .error
        }

        // Warning messages
        if lowercased.contains("warning") || lowercased.contains("careful") ||
           lowercased.contains("hungry") || lowercased.contains("weak") {
            return .warning
        }

        // Success messages
        if lowercased.contains("welcome") || lowercased.contains("success") ||
           lowercased.contains("you kill") || lowercased.contains("you hit") {
            return .success
        }

        // Default to info
        return .info
    }

    enum MessageType {
        case info, warning, error, success, ambient
    }

    /// Calculate priority for sorting (higher = more important)
    var priority: Int {
        if attributes.isUrgent { return 3 }
        if attributes.isBold { return 2 }
        if type == .error { return 3 }
        if type == .warning { return 2 }
        if attributes.isDim { return 0 }
        return 1 // normal
    }

    /// Calculate opacity based on turn age for turn-based fading
    /// - Parameter currentTurn: The current game turn number
    /// - Returns: Opacity value between 0.5 and 1.0
    func opacity(currentTurn: Int) -> Double {
        let turnsSince = currentTurn - turnNumber

        // Current turn: full opacity
        if turnsSince == 0 {
            return 1.0
        }

        // Last turn: 90% opacity
        if turnsSince == 1 {
            return 0.9
        }

        // Progressive fade for older turns
        // Turn 2: 0.75, Turn 3: 0.60, Turn 4: 0.45
        let fade = max(0.0, 1.0 - (Double(turnsSince - 1) * 0.15))

        // Minimum 50% opacity (never fully invisible)
        return max(0.5, fade)
    }
}

extension GameMessage {
    // DEAD CODE REMOVED: toToastType() - MessageToast component no longer exists

    /// Get SwiftUI font weight based on attributes
    var fontWeight: Font.Weight {
        if attributes.isBold { return .bold }
        if attributes.isDim { return .light }
        return .regular
    }

    /// Get text color based on type and attributes
    func textColor(baseColor: Color = .white) -> Color {
        if attributes.isInverse {
            return .black
        }

        switch type {
        case .error:
            return .red
        case .warning:
            return .orange
        case .success:
            return .green
        case .ambient:
            return baseColor.opacity(0.7)
        case .info:
            return baseColor
        }
    }

    /// Get background color if inverse attribute is set
    var backgroundColor: Color? {
        if attributes.isInverse {
            return textColor(baseColor: .white)
        }
        return nil
    }
}
