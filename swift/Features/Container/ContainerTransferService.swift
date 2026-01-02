import Foundation
import SwiftUI

// MARK: - C Bridge Imports

@_silgen_name("ios_get_floor_containers_at_player")
private func ios_get_floor_containers_at_player(_ buffer: UnsafeMutablePointer<IOSFloorContainerInfo>, _ max: Int32) -> Int32

@_silgen_name("ios_set_current_container")
private func ios_set_current_container(_ container_o_id: UInt32) -> Int32

@_silgen_name("ios_put_item_in_container")
private func ios_put_item_in_container(_ invlet: CChar) -> Int32

@_silgen_name("ios_take_item_from_container")
private func ios_take_item_from_container(_ item_index: Int32) -> Int32

@_silgen_name("ios_take_all_from_container")
private func ios_take_all_from_container() -> Int32

@_silgen_name("ios_clear_current_container")
private func ios_clear_current_container()

@_silgen_name("ios_get_current_container_contents")
private func ios_get_current_container_contents(_ buffer: UnsafeMutablePointer<IOSContainerItemInfo>, _ max: Int32) -> Int32

@_silgen_name("ios_set_inventory_container")
private func ios_set_inventory_container(_ invlet: CChar) -> Int32

@_silgen_name("ios_get_inventory_container_id")
private func ios_get_inventory_container_id(_ invlet: CChar) -> UInt32

// MARK: - C Struct Mirrors

/// Mirror of IOSFloorContainerInfo from ios_container_bridge.h
struct IOSFloorContainerInfo {
    var o_id: UInt32 = 0
    var name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var item_count: Int32 = 0
    var is_locked: Bool = false
    var is_broken: Bool = false  // Kicked/forced open
    var is_trapped: Bool = false
    var oclass: Int32 = 0
}

/// Mirror of IOSContainerItemInfo from ios_container_bridge.h
struct IOSContainerItemInfo {
    var o_id: UInt32 = 0
    var name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var quantity: Int32 = 0
    var oclass: Int32 = 0
    var buc_status: CChar = 0
    var is_container: Bool = false
}

// MARK: - Swift Models

/// Floor container info for Swift UI
struct FloorContainerInfo: Identifiable {
    let id: UInt32  // o_id
    let name: String
    let itemCount: Int
    let isLocked: Bool
    let isBroken: Bool  // Kicked/forced open container
    let isTrapped: Bool
    
    var icon: String {
        if name.contains("bag of holding") {
            return "sparkles.rectangle.stack"
        }
        if name.contains("bag") || name.contains("sack") {
            return "bag.fill"
        }
        if name.contains("chest") {
            return "archivebox.fill"
        }
        if name.contains("ice box") {
            return "snowflake"
        }
        return "shippingbox"
    }
    
    var iconColor: Color {
        if name.contains("bag of holding") {
            return .purple
        }
        if name.contains("ice box") {
            return .cyan
        }
        if isLocked {
            return .nethackError
        }
        return .nethackAccent
    }
}

/// Container item info for Swift UI
struct ContainerItemInfo: Identifiable {
    let id: UInt32  // o_id
    let name: String
    let index: Int  // Position in container for take operation
    let quantity: Int
    let bucStatus: ItemBUCStatus
    let isContainer: Bool

    var displayName: String {
        guard quantity > 1 else { return name }
        return name  // Name already includes quantity from doname()
    }
}

/// Result of a transfer operation
enum TransferResult {
    case success
    case failed(String)
    case bohExplosion  // Bag of Holding would explode
}

// MARK: - Container Transfer Service

/// Service for managing floor container operations
/// Wrapper around ios_container_bridge.c functions
///
/// THREAD SAFETY CONTRACT:
/// - All methods are @MainActor isolated (run on main thread)
/// - C bridge functions are mutex-protected against concurrent Swift calls
/// - Container operations are safe ONLY when game thread is blocked waiting for input
/// - The C bridge checks program_state.gameover to prevent access during shutdown
/// - Do NOT call container operations during active game thread processing
@MainActor
@Observable
final class ContainerTransferService {
    static let shared = ContainerTransferService()

    private(set) var currentContainerID: UInt32?
    private(set) var containerContents: [ContainerItemInfo] = []
    private(set) var lastError: String?

    private let maxItems = 256  // Max items to fetch from container

    private init() {}
    
    // MARK: - Floor Container Discovery
    
    /// Get all floor containers at player's current position
    func getFloorContainers() -> [FloorContainerInfo] {
        var buffer = [IOSFloorContainerInfo](repeating: IOSFloorContainerInfo(), count: 16)
        let count = ios_get_floor_containers_at_player(&buffer, 16)
        
        guard count > 0 else { return [] }
        
        return (0..<Int(count)).compactMap { i in
            let info = buffer[i]
            let name = withUnsafePointer(to: info.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { cStr in
                    String(cString: cStr)
                }
            }
            
            return FloorContainerInfo(
                id: info.o_id,
                name: name,
                itemCount: Int(info.item_count),
                isLocked: info.is_locked,
                isBroken: info.is_broken,
                isTrapped: info.is_trapped
            )
        }
    }
    
    // MARK: - Container Selection
    
    /// Set the current container for operations
    /// - Parameter containerID: o_id of the floor container
    /// - Returns: true if container was successfully set
    func setCurrentContainer(id containerID: UInt32) -> Bool {
        let result = ios_set_current_container(containerID)

        guard result == 1 else {
            currentContainerID = nil
            lastError = "Could not open container (locked or not found)"
            return false
        }

        currentContainerID = containerID
        lastError = nil

        // Refresh contents
        refreshContainerContents()

        return true
    }

    /// Set current container from inventory item by invlet (for Apply action)
    /// Returns the container's o_id if successful, nil otherwise
    func setInventoryContainer(invlet: Character) -> UInt32? {
        guard let ascii = invlet.asciiValue else {
            lastError = "Invalid inventory letter"
            return nil
        }

        let result = ios_set_inventory_container(CChar(bitPattern: UInt8(ascii)))

        guard result == 1 else {
            currentContainerID = nil
            lastError = "Could not open container (not found, not a container, or locked)"
            return nil
        }

        // Get the container's o_id for tracking
        let containerId = ios_get_inventory_container_id(CChar(bitPattern: UInt8(ascii)))
        guard containerId != 0 else {
            lastError = "Could not get container ID"
            return nil
        }

        currentContainerID = containerId
        lastError = nil

        // Refresh contents
        refreshContainerContents()

        return containerId
    }

    /// Get FloorContainerInfo for an inventory container
    /// Creates a FloorContainerInfo from an inventory item for use with ContainerTransferView
    func getInventoryContainerInfo(item: NetHackItem) -> FloorContainerInfo? {
        guard item.isContainer else { return nil }
        guard let ascii = item.invlet.asciiValue else { return nil }

        let containerId = ios_get_inventory_container_id(CChar(bitPattern: UInt8(ascii)))
        guard containerId != 0 else { return nil }

        return FloorContainerInfo(
            id: containerId,
            name: item.fullName,
            itemCount: 0, // Will be populated when container is opened
            isLocked: false,
            isBroken: false,
            isTrapped: false
        )
    }

    /// Clear the current container reference
    func clearCurrentContainer() {
        ios_clear_current_container()
        currentContainerID = nil
        containerContents = []
    }
    
    // MARK: - Container Contents
    
    /// Refresh the contents of the current container
    func refreshContainerContents() {
        guard currentContainerID != nil else {
            containerContents = []
            return
        }
        
        var buffer = [IOSContainerItemInfo](repeating: IOSContainerItemInfo(), count: maxItems)
        let count = ios_get_current_container_contents(&buffer, Int32(maxItems))

        guard count > 0 else {
            containerContents = []
            return
        }

        containerContents = (0..<Int(count)).map { i in
            let info = buffer[i]
            let name = withUnsafePointer(to: info.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 256) { cStr in
                    String(cString: cStr)
                }
            }

            let bucStatus: ItemBUCStatus
            switch info.buc_status {
            case CChar(UnicodeScalar("B").value): bucStatus = .blessed
            case CChar(UnicodeScalar("C").value): bucStatus = .cursed
            case CChar(UnicodeScalar("U").value): bucStatus = .uncursed
            default: bucStatus = .unknown
            }

            return ContainerItemInfo(
                id: info.o_id,
                name: name,
                index: i,  // Use loop index as position in container
                quantity: Int(info.quantity),
                bucStatus: bucStatus,
                isContainer: info.is_container
            )
        }
    }
    
    // MARK: - Transfer Operations
    
    /// Put an inventory item into the current container
    /// - Parameter invlet: Inventory letter of the item
    /// - Returns: TransferResult indicating success/failure
    func putItemInContainer(invlet: Character) -> TransferResult {
        guard currentContainerID != nil else {
            return .failed("No container selected")
        }
        
        guard let ascii = invlet.asciiValue else {
            return .failed("Invalid inventory letter")
        }
        
        let result = ios_put_item_in_container(CChar(bitPattern: UInt8(ascii)))
        
        switch result {
        case 1:
            refreshContainerContents()
            return .success
        case -1:
            return .bohExplosion
        default:
            return .failed("Cannot put item in container")
        }
    }
    
    /// Take an item from the current container
    /// - Parameter index: Index of item in container
    /// - Returns: true if successful
    func takeItemFromContainer(index: Int) -> Bool {
        guard currentContainerID != nil else { return false }
        
        let result = ios_take_item_from_container(Int32(index))
        
        guard result == 1 else { return false }
        
        refreshContainerContents()
        return true
    }
    
    /// Take all items from the current container
    /// - Returns: Number of items taken
    func takeAllFromContainer() -> Int {
        guard currentContainerID != nil else { return 0 }
        
        let count = ios_take_all_from_container()
        
        refreshContainerContents()
        return Int(count)
    }
}
