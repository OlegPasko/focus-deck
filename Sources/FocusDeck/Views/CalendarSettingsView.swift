import SwiftUI
import FocusDeckKit

struct CalendarSettingsView: View {
    @ObservedObject var calendar: CalendarController
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show your next event above Current Focus. Uses accounts connected to Apple Calendar, including Google, Outlook, and iCloud.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            HStack {
                if settings.settings.calendarEnabled && calendar.access == .allowed {
                    Label("Calendar connected", systemImage: "checkmark.circle")
                        .font(.system(size: 13))
                    Spacer()
                    Button("Disconnect") { calendar.disconnect() }
                } else {
                    Button(calendar.isConnecting ? "Connecting…" : "Connect Calendar") {
                        Task { await calendar.connect() }
                    }
                    .disabled(calendar.isConnecting)
                }
                Button("Calendar accounts…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preferences.internetaccounts")!)
                }
            }
            Stepper(value: $settings.settings.calendarLeadMinutes, in: 1...120) {
                Text("Show \(settings.settings.calendarLeadMinutes) min before the event")
                    .font(.system(size: 13)).monospacedDigit()
            }
            Text("Dim until the final minute, then white with a border. Shows “Starting now” for up to one minute after the start. All-day, cancelled, and declined events are skipped.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            if settings.settings.calendarEnabled && calendar.access == .allowed {
                Toggle("All calendars", isOn: Binding(
                    get: { settings.settings.selectedCalendarIDs == nil },
                    set: { settings.settings.selectedCalendarIDs = $0 ? nil : calendar.calendars.map(\.id) }
                ))
                .toggleStyle(.checkbox)
                if settings.settings.selectedCalendarIDs != nil {
                    ForEach(calendar.calendars) { choice in
                        Toggle("\(choice.title) · \(choice.account)", isOn: Binding(
                            get: { settings.settings.selectedCalendarIDs?.contains(choice.id) ?? true },
                            set: { selected in
                                var ids = settings.settings.selectedCalendarIDs ?? calendar.calendars.map(\.id)
                                ids.removeAll { $0 == choice.id }
                                if selected { ids.append(choice.id) }
                                settings.settings.selectedCalendarIDs = ids
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    if settings.settings.selectedCalendarIDs?.isEmpty == true {
                        Text("Select at least one calendar to show reminders.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if calendar.calendars.isEmpty {
                    Text("No calendars found. Add an account in Calendar accounts and enable Calendars for it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let error = calendar.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange)
            } else if settings.settings.calendarEnabled && calendar.access != .allowed {
                Text("Calendar access is off. Allow it in System Settings → Privacy & Security → Calendars.")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            if calendar.access == .denied || calendar.access == .restricted {
                Button("Calendar privacy settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
        .onAppear { calendar.update(force: true) }
    }
}
