import SwiftUI

struct MeetingReminderView: View {
    let event: MeetingEvent
    let now: Date

    var body: some View {
        let urgent = event.isUrgent(at: now)
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 15))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(event.countdown(at: now)).monospacedDigit()
                    Text("·")
                    Text(event.start, style: .time)
                }
                .font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(urgent ? 1 : 0.45))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(urgent ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(urgent ? 0.9 : 0), lineWidth: 1))
        .help(event.title)
        .accessibilityElement(children: .combine)
    }
}
