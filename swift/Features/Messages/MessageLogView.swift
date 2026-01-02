import SwiftUI

// MARK: - Message Log View

/// Fullscreen message log sheet showing complete game message history.
/// Accessed by tapping on the notification toast area.
struct MessageLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyManager = MessageHistoryManager.shared

    private let isPhone = ScalingEnvironment.isPhone

    var body: some View {
        ZStack {
            // Dark glass background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                Divider()
                    .background(Color.white.opacity(0.2))

                // Message list
                messageList
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "text.bubble.fill")
                .font(.title2)
                .foregroundColor(.cyan)

            Text("Message Log")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Text("\(historyManager.messages.count) messages")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)  // iOS minimum touch target
        }
        .padding()
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(historyManager.messages) { message in
                        MessageLogRow(message: message, isPhone: isPhone)
                            .id(message.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear {
                // Auto-scroll to newest message (at bottom)
                if let lastMessage = historyManager.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message Log Row

private struct MessageLogRow: View {
    let message: GameMessage
    let isPhone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Turn number badge
            Text("T\(message.turnNumber)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: isPhone ? 32 : 40)

            // Message content
            messageText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .cornerRadius(6)
    }

    private var messageText: some View {
        Text(displayText)
            .font(isPhone ? .caption : .callout)
            .fontWeight(message.fontWeight)
            .italic(message.attributes.isItalic)
            .underline(message.attributes.isUnderline)
            .foregroundColor(message.textColor())
            .background(message.backgroundColor)
    }

    private var displayText: String {
        if message.count > 1 {
            return "\(message.text) (x\(message.count))"
        }
        return message.text
    }

    private var rowBackground: Color {
        // Subtle highlight for important messages
        switch message.type {
        case .error:
            return Color.red.opacity(0.1)
        case .warning:
            return Color.orange.opacity(0.08)
        case .success:
            return Color.green.opacity(0.08)
        default:
            return Color.white.opacity(0.03)
        }
    }
}

// MARK: - Preview

#Preview {
    MessageLogView()
}
