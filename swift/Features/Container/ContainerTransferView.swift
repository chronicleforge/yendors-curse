import SwiftUI

// MARK: - Container Transfer View

/// Split-screen view for transferring items between inventory and floor containers
/// 
/// Layout:
/// ```
/// +----------------------------+---------------------------+
/// |  INVENTORY                 |  CONTAINER                |
/// +----------------------------+---------------------------+
/// |                            |   [ TAKE ALL ]            |
/// |  sword            [>]      |   [<]  gem                |
/// |  shield           [>]      |   [<]  apple              |
/// |  potion           [>]      |                           |
/// |                            |   [ CLOSE ]               |
/// +----------------------------+---------------------------+
/// ```
///
/// Reference: SWIFTUI-L-002 (ZStack for overlays), SWIFTUI-A-001 (spring animations)
struct ContainerTransferView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @EnvironmentObject var overlayManager: GameOverlayManager
    
    @State private var transferService = ContainerTransferService.shared
    
    let container: FloorContainerInfo
    
    @State private var showBohWarning = false
    @State private var pendingBohItem: Character?
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let isPhone = ScalingEnvironment.isPhone
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.width < 600  // iPhone or narrow iPad
            
            if isCompact {
                // Vertical stack for iPhone
                verticalLayout(geometry: geometry)
            } else {
                // Horizontal split for iPad
                horizontalLayout(geometry: geometry)
            }
        }
        .background(.ultraThickMaterial)
        .onAppear {
            setupContainer()
        }
        .onDisappear {
            transferService.clearCurrentContainer()
        }
        .alert("Bag of Holding Warning", isPresented: $showBohWarning) {
            Button("Cancel", role: .cancel) {
                pendingBohItem = nil
            }
            // NOTE: Not providing "Proceed" button - BoH explosion is too dangerous
        } message: {
            Text("Putting this item in the Bag of Holding would cause it to EXPLODE, destroying all contents!")
        }
        .alert("Transfer Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Layouts
    
    /// Horizontal split layout for iPad (50/50)
    @ViewBuilder
    private func horizontalLayout(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // Left: Inventory Panel
            inventoryPanel
                .frame(width: geometry.size.width * 0.5)
            
            Divider()
                .background(Color.nethackGray400)
            
            // Right: Container Panel
            containerPanel
                .frame(width: geometry.size.width * 0.5)
        }
    }
    
    /// Vertical stacked layout for iPhone
    @ViewBuilder
    private func verticalLayout(geometry: GeometryProxy) -> some View {
        TabView {
            // Tab 1: Inventory
            inventoryPanel
                .tabItem {
                    Label("Inventory", systemImage: "backpack.fill")
                }
            
            // Tab 2: Container
            containerPanel
                .tabItem {
                    Label(container.name, systemImage: container.icon)
                }
        }
        .accentColor(.nethackAccent)
    }
    
    // MARK: - Inventory Panel
    
    private var inventoryPanel: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader(
                title: "Inventory",
                icon: "backpack.fill",
                color: .nethackGray700
            )
            
            // Content
            if overlayManager.items.isEmpty {
                emptyState(
                    icon: "tray",
                    title: "Inventory Empty",
                    subtitle: "Nothing to put in container"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(transferableItems) { item in
                            ContainerItemRow(
                                item: item,
                                direction: .toContainer,
                                onTransfer: { handlePutItem(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
    
    // MARK: - Container Panel
    
    private var containerPanel: some View {
        VStack(spacing: 0) {
            // Header
            containerHeader
            
            // Take All Button
            if !transferService.containerContents.isEmpty {
                takeAllButton
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            
            // Content
            if transferService.containerContents.isEmpty {
                emptyState(
                    icon: "shippingbox",
                    title: "Container Empty",
                    subtitle: "Put items in from your inventory"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(transferService.containerContents) { item in
                            ContainerContentRow(
                                item: item,
                                onTake: { handleTakeItem(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            
            // Close Button
            closeButton
                .padding(12)
        }
    }
    
    // MARK: - Header Components
    
    private func panelHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: isPhone ? 16 : 18, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: isPhone ? 15 : 17, weight: .bold))
                .foregroundColor(.nethackGray900)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
    
    private var containerHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: container.icon)
                .font(.system(size: isPhone ? 18 : 20, weight: .bold))
                .foregroundColor(container.iconColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.system(size: isPhone ? 14 : 16, weight: .bold))
                    .foregroundColor(.nethackGray900)
                    .lineLimit(nil)
                
                HStack(spacing: 6) {
                    Text("\(transferService.containerContents.count) items")
                        .font(.system(size: isPhone ? 11 : 12))
                        .foregroundColor(.nethackGray500)
                    
                    if container.isTrapped {
                        Text("TRAPPED")
                            .font(.system(size: isPhone ? 9 : 10, weight: .bold))
                            .foregroundColor(.nethackError)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Color.nethackError.opacity(0.2))
                            )
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                )
        )
    }
    
    // MARK: - Buttons
    
    private var takeAllButton: some View {
        Button(action: handleTakeAll) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: isPhone ? 14 : 16))
                Text("TAKE ALL")
                    .font(.system(size: isPhone ? 13 : 14, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)  // Minimum touch target
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.nethackSuccess.opacity(0.85))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: isPhone ? 14 : 16))
                Text("CLOSE")
                    .font(.system(size: isPhone ? 13 : 14, weight: .bold))
            }
            .foregroundColor(.nethackGray800)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.nethackGray500.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: isPhone ? 40 : 56))
                .foregroundColor(.nethackGray400)
            
            Text(title)
                .font(.system(size: isPhone ? 16 : 18, weight: .bold))
                .foregroundColor(.nethackGray600)
            
            Text(subtitle)
                .font(.system(size: isPhone ? 13 : 14))
                .foregroundColor(.nethackGray500)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    /// Inventory items that can be transferred (excludes worn/wielded)
    private var transferableItems: [NetHackItem] {
        overlayManager.items.filter { item in
            // Allow all items - the row will show disabled state for worn/wielded
            true
        }
    }
    
    // MARK: - Actions
    
    private func setupContainer() {
        // Refresh inventory
        overlayManager.updateInventory()

        // Set current container
        guard transferService.setCurrentContainer(id: container.id) else {
            errorMessage = transferService.lastError ?? "Could not open container"
            showError = true
            return
        }
    }
    
    private func handlePutItem(_ item: NetHackItem) {
        let result = transferService.putItemInContainer(invlet: item.invlet)
        
        switch result {
        case .success:
            // Haptic success feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Refresh inventory after transfer
            overlayManager.updateInventory()
            
        case .bohExplosion:
            // Show warning - do not proceed
            pendingBohItem = item.invlet
            showBohWarning = true
            
        case .failed(let reason):
            errorMessage = reason
            showError = true
        }
    }
    
    private func handleTakeItem(_ item: ContainerItemInfo) {
        let success = transferService.takeItemFromContainer(index: item.index)
        
        guard success else {
            errorMessage = "Could not take item"
            showError = true
            return
        }
        
        // Haptic success feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Refresh inventory after transfer
        overlayManager.updateInventory()
    }
    
    private func handleTakeAll() {
        let count = transferService.takeAllFromContainer()
        
        guard count > 0 else {
            // Could be encumbrance or artifact restriction
            errorMessage = "Could not take all items (encumbrance or restriction)"
            showError = true
            return
        }
        
        // Haptic success feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Refresh inventory after transfer
        overlayManager.updateInventory()
    }
}

// MARK: - Preview

#Preview {
    ContainerTransferView(
        container: FloorContainerInfo(
            id: 1,
            name: "large box",
            itemCount: 3,
            isLocked: false,
            isBroken: false,
            isTrapped: false
        )
    )
    .environmentObject(GameOverlayManager())
}
