import SwiftUI
import FocusDeckKit

/// Quiet typography, sized from the space actually available after margins.
struct FocusTitleView: View {
    let item: FocusItem?
    let settings: FocusSettings
    var emptyText = "One thing\nat a time."
    var meeting: MeetingEvent?
    var now = Date()

    var body: some View {
        GeometryReader { geometry in
            let text = displayText
            let lines = geometry.size.width < 700 ? 5 : 4
            let size = TitleFitter.fontSize(for: text,
                in: CGSize(width: geometry.size.width, height: max(60, geometry.size.height - (meeting == nil ? 65 : 145))),
                scale: CGFloat(settings.textScale), maxLines: lines, padding: 0)
            VStack(alignment: .leading, spacing: 18) {
                if let meeting {
                    MeetingReminderView(event: meeting, now: now)
                        .frame(maxWidth: 480, alignment: .leading)
                }
                HStack(spacing: 9) {
                    Circle().fill(Color(red: 0.94, green: 0.65, blue: 0.62)).frame(width: 6, height: 6)
                    Text(item == nil ? "A LITTLE SPACE TO FOCUS" : "CURRENT FOCUS")
                        .tracking(3)
                    if let project = item?.project, !project.isEmpty {
                        Text("/  " + project).tracking(1).lineLimit(1)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))

                Text(text)
                    .font(.system(size: size, weight: .bold))
                    .tracking(-size * 0.025)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(size * 0.02)
                    .lineLimit(lines)
                    .minimumScaleFactor(0.15)
                    .fixedSize(horizontal: false, vertical: false)
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(item?.title ?? emptyText)

                if settings.showCoverTitle, let detail = item?.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: max(13, min(20, size * 0.22))))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 40)
                    .fill(.black.opacity(settings.titleScrimStrength * 0.5))
                    .blur(radius: 50)
                    .padding(-20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }

    private var displayText: String {
        guard let title = item?.title, !title.isEmpty else { return emptyText }
        return settings.uppercase ? title.uppercased() : title
    }
}
