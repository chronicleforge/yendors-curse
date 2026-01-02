import Foundation

// Safe array subscript - prevents index out of bounds crashes
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
