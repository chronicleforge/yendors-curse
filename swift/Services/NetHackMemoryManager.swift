import Foundation

/// Memory manager for NetHack using Apple's zone allocation
/// Provides monitoring and statistics for the zone-based memory system
@objc class NetHackMemoryManager: NSObject {

    /// Singleton instance
    @objc static let shared = NetHackMemoryManager()

    private override init() {
        super.init()
    }

    /// Get current memory statistics
    @objc func getMemoryStats() -> [String: Any] {
        var bytesAllocated: size_t = 0
        var numAllocations: size_t = 0

        // Call C function to get stats
        nethack_zone_stats(&bytesAllocated, &numAllocations)

        return [
            "bytesAllocated": bytesAllocated,
            "numAllocations": numAllocations,
            "formattedSize": formatBytes(bytesAllocated)
        ]
    }

    /// Print detailed memory statistics to console
    @objc func printMemoryStats() {
        nethack_zone_print_stats()

        let stats = getMemoryStats()
        print("📊 NetHack Memory Stats:")
        print("   Allocations: \(stats["numAllocations"] ?? 0)")
        print("   Total Size: \(stats["formattedSize"] ?? "0 bytes")")
    }

    /// Perform a complete memory zone restart
    /// This destroys all game memory and creates a fresh zone
    @objc func restartMemoryZone() {
        print("🔄 Performing memory zone restart...")

        // Get stats before restart
        let beforeStats = getMemoryStats()
        print("   Before: \(beforeStats["formattedSize"] ?? "0") in \(beforeStats["numAllocations"] ?? 0) allocations")

        // Perform the restart
        nethack_zone_restart()

        // Get stats after restart
        let afterStats = getMemoryStats()
        print("   After: \(afterStats["formattedSize"] ?? "0") in \(afterStats["numAllocations"] ?? 0) allocations")

        print("✅ Memory zone restart complete!")
    }

    /// Complete shutdown of all memory zones
    @objc func shutdownMemoryZones() {
        print("🛑 Shutting down all memory zones...")
        nethack_zone_shutdown()
        print("✅ Memory zones shut down")
    }

    /// Check if debug mode should show memory stats
    @objc var showMemoryDebugInfo: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Format bytes to human-readable string
    private func formatBytes(_ bytes: size_t) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Monitor memory during gameplay (can be called periodically)
    @objc func monitorMemory() {
        guard showMemoryDebugInfo else { return }

        let stats = getMemoryStats()
        let allocations = stats["numAllocations"] as? size_t ?? 0

        // Warn if memory usage seems excessive
        if allocations > 100000 {
            print("⚠️ High memory allocation count: \(allocations)")
        }
    }

    /// Get a memory report suitable for debugging
    @objc func getMemoryReport() -> String {
        let stats = getMemoryStats()

        var report = "=== NetHack Memory Report ===\n"
        report += "Allocations: \(stats["numAllocations"] ?? 0)\n"
        report += "Total Size: \(stats["formattedSize"] ?? "0 bytes")\n"
        report += "Zone System: Active\n"

        #if DEBUG
        report += "Debug Mode: Enabled\n"
        #else
        report += "Debug Mode: Disabled\n"
        #endif

        return report
    }
}

// MARK: - Bridge to C functions
// These are defined in nethack_zone.c
@_silgen_name("nethack_zone_stats")
func nethack_zone_stats(_ bytes_allocated: UnsafeMutablePointer<size_t>?,
                        _ num_allocations: UnsafeMutablePointer<size_t>?)

@_silgen_name("nethack_zone_print_stats")
func nethack_zone_print_stats()

@_silgen_name("nethack_zone_restart")
func nethack_zone_restart()

@_silgen_name("nethack_zone_shutdown")
func nethack_zone_shutdown()