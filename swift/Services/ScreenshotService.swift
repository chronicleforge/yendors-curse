import SwiftUI
import UIKit
import SceneKit

/// Service for capturing and managing screenshots of the game view
///
/// Flow:
/// 1. NetHackGameView registers its SceneKit view with registerSceneView()
/// 2. When saving, coordinator calls captureAndSaveScreenshot()
/// 3. Screenshot is captured directly from SCNView and saved to character directory
@MainActor
class ScreenshotService {
    static let shared = ScreenshotService()

    /// The current SceneKit view for screenshot capture
    private weak var sceneView: SCNView?

    private init() {}

    // MARK: - Registration

    /// Register the SceneKit view for screenshot capture
    func registerSceneView(_ view: SCNView) {
        sceneView = view
        print("[ScreenshotService] SceneKit view registered for screenshot capture")
    }

    /// Unregister the scene view
    func unregisterSceneView() {
        sceneView = nil
        print("[ScreenshotService] SceneKit view unregistered")
    }

    // MARK: - Screenshot Capture

    /// Capture a screenshot of the registered SceneKit view
    /// Returns: UIImage if successful, nil otherwise
    func captureScreenshot() -> UIImage? {
        print("[ScreenshotService] 📸 captureScreenshot() called")

        guard let sceneView = sceneView else {
            print("[ScreenshotService] ❌ No SceneKit view registered for capture")
            return nil
        }

        print("[ScreenshotService] ✅ SceneKit view is registered, capturing snapshot...")

        // Use SCNView's built-in snapshot method - this WORKS with SceneKit!
        let snapshot = sceneView.snapshot()

        print("[ScreenshotService] ✅ Screenshot captured successfully!")
        print("[ScreenshotService]   Size: \(snapshot.size.width)x\(snapshot.size.height)")
        print("[ScreenshotService]   Scale: \(snapshot.scale)")

        return snapshot
    }

    // MARK: - Save Screenshot

    /// Save screenshot to character directory
    /// - Parameters:
    ///   - image: The screenshot image
    ///   - characterName: The character name
    /// - Returns: true if successful, false otherwise
    func saveScreenshot(_ image: UIImage, for characterName: String) -> Bool {
        print("[ScreenshotService] 💾 saveScreenshot() called for: \(characterName)")

        guard let pngData = image.pngData() else {
            print("[ScreenshotService] ❌ Failed to convert image to PNG")
            return false
        }

        print("[ScreenshotService] ✅ PNG data created: \(pngData.count) bytes")

        // Get character directory path
        let characterDir = getCharacterDirectory(characterName)
        print("[ScreenshotService] Character directory: \(characterDir)")

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: characterDir) {
            print("[ScreenshotService] ⚠️  Directory doesn't exist, creating...")
            do {
                try FileManager.default.createDirectory(atPath: characterDir, withIntermediateDirectories: true)
                print("[ScreenshotService] ✅ Directory created")
            } catch {
                print("[ScreenshotService] ❌ Failed to create directory: \(error)")
                return false
            }
        } else {
            print("[ScreenshotService] ✅ Directory exists")
        }

        // Screenshot path
        let screenshotPath = "\(characterDir)/screenshot.png"
        let url = URL(fileURLWithPath: screenshotPath)

        print("[ScreenshotService] Writing to: \(screenshotPath)")

        do {
            try pngData.write(to: url)
            print("[ScreenshotService] ✅ Screenshot saved successfully!")

            // Verify file was written
            if FileManager.default.fileExists(atPath: screenshotPath) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: screenshotPath)
                let size = attrs?[.size] as? Int64 ?? 0
                print("[ScreenshotService] ✅ File verified: \(size) bytes")
            }

            return true
        } catch {
            print("[ScreenshotService] ❌ Failed to save screenshot: \(error)")
            return false
        }
    }

    /// Capture and save screenshot in one operation
    /// - Parameter characterName: The character name
    /// - Returns: true if successful, false otherwise
    func captureAndSaveScreenshot(for characterName: String) -> Bool {
        print("[ScreenshotService] 🎬 captureAndSaveScreenshot() called for: \(characterName)")
        print("[ScreenshotService] 🎬 About to call captureScreenshot()...")

        guard let screenshot = captureScreenshot() else {
            print("[ScreenshotService] ❌ captureScreenshot() returned nil")
            return false
        }

        print("[ScreenshotService] ✅ captureScreenshot() succeeded, now saving...")
        return saveScreenshot(screenshot, for: characterName)
    }

    // MARK: - Load Screenshot

    /// Load screenshot for a character
    /// - Parameter characterName: The character name
    /// - Returns: UIImage if exists, nil otherwise
    func loadScreenshot(for characterName: String) -> UIImage? {
        let characterDir = getCharacterDirectory(characterName)
        let screenshotPath = "\(characterDir)/screenshot.png"

        guard FileManager.default.fileExists(atPath: screenshotPath) else {
            return nil
        }

        return UIImage(contentsOfFile: screenshotPath)
    }

    // MARK: - Helpers

    private func getCharacterDirectory(_ characterName: String) -> String {
        return CharacterSanitization.getCharacterDirectory(characterName)
    }
}
