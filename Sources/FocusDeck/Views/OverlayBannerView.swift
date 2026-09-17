import SwiftUI
import FocusDeckKit

/// Short banner for incoming news (for example, a message from another agent).
struct OverlayBannerView: View {
    let message: OverlayMessage

    private var tint: Color {
        switch message.kind {
        case "warn": return .orange
        case "agent": return .cyan
        default: return .white
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.kind == "agent" ? "sparkles" : "bell.badge")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle = message.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
        .padding(.horizontal, 40)
    }
}
