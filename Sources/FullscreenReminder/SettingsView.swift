import AppKit
import EventKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var calendarSelectionViewModel: CalendarSelectionViewModel
    @ObservedObject private var appUpdater = AppUpdater.shared
    @AppStorage(ReminderPreferences.notifyOneMinuteKey) private var notifyOneMinute = true
    @AppStorage(ReminderPreferences.notifyFiveMinutesKey) private var notifyFiveMinutes = false
    @AppStorage(ReminderPreferences.notifyFifteenMinutesKey) private var notifyFifteenMinutes = false
    @AppStorage(ReminderPreferences.notificationSoundNameKey) private var selectedSoundName =
        ReminderPreferences.defaultSoundName
    @AppStorage(ReminderPreferences.snoozeMinutesKey) private var snoozeMinutes =
        ReminderPreferences.defaultSnoozeMinutes
    @AppStorage(ReminderPreferences.showAllDayEventsKey) private var showAllDayEvents = true
    @AppStorage(ReminderPreferences.showMeetingTitleInMenuKey) private var showMeetingTitleInMenu =
        true
    @AppStorage(ReminderPreferences.reminderStyleKey) private var reminderStyle = ReminderStyle.glassmorphism
    @AppStorage(ReminderPreferences.daysToDisplayKey) private var daysToDisplay =
        ReminderPreferences.defaultDaysToDisplay

    @State private var previewSound: NSSound?
    @State private var launchAtLoginEnabled = LaunchAtLoginManager.isEnabled()
    @State private var launchAtLoginErrorMessage: String?
    @State private var isShowingLaunchAtLoginError = false
    @State private var isHandlingLaunchAtLoginChange = false

    private var soundOptions: [String] {
        var names = ReminderPreferences.availableSoundNames
        if !names.contains(selectedSoundName) {
            names.insert(selectedSoundName, at: 0)
        }
        return names
    }

    init(
        calendarSelectionViewModel: CalendarSelectionViewModel = CalendarSelectionViewModel(
            eventStore: EKEventStore())
    ) {
        self._calendarSelectionViewModel = ObservedObject(wrappedValue: calendarSelectionViewModel)
    }

    var body: some View {
        Form {
            Section(header: sectionHeader("General")) {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        guard !isHandlingLaunchAtLoginChange else { return }
                        isHandlingLaunchAtLoginChange = true

                        do {
                            try LaunchAtLoginManager.setEnabled(newValue)
                        } catch {
                            launchAtLoginErrorMessage = error.localizedDescription
                            launchAtLoginEnabled.toggle()
                            isShowingLaunchAtLoginError = true
                        }

                        isHandlingLaunchAtLoginChange = false
                    }

                Toggle("Show Meeting Title in Menu Bar", isOn: $showMeetingTitleInMenu)
                    .onChange(of: showMeetingTitleInMenu) { _, _ in
                        NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                    }

                Toggle("Show All-Day Events", isOn: $showAllDayEvents)
                    .onChange(of: showAllDayEvents) { _, _ in
                        NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                    }

                HStack {
                    Text("Reminder Style:")
                    Spacer()
                    Picker("", selection: $reminderStyle) {
                        ForEach(ReminderStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    // An explicit width: with .fixedSize() the Form squeezed it to just the arrows.
                    .frame(width: 150)
                    
                    Button(action: {
                        NotificationCenter.default.post(name: .previewReminder, object: nil)
                    }) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Preview Reminder")
                }

                HStack {
                    Text("Days to show:")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(daysToDisplay)")
                            .font(.body.monospacedDigit())
                            .fontWeight(.bold)
                        Text(daysToDisplay == 1 ? "day" : "days")
                    }
                    .foregroundColor(.secondary)
                    
                    Stepper("", value: $daysToDisplay, in: 1...30, step: 1)
                        .labelsHidden()
                }
                .onChange(of: daysToDisplay) { _, newValue in
                    ReminderPreferences.daysToDisplay = newValue
                    NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                }
            }

            Section(header: sectionHeader("Alerts")) {
                Text("Remind me:")
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("1 minute before", isOn: $notifyOneMinute)
                        .onChange(of: notifyOneMinute) { _, _ in
                            NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                        }
                    Toggle("5 minutes before", isOn: $notifyFiveMinutes)
                        .onChange(of: notifyFiveMinutes) { _, _ in
                            NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                        }
                    Toggle("15 minutes before", isOn: $notifyFifteenMinutes)
                        .onChange(of: notifyFifteenMinutes) { _, _ in
                            NotificationCenter.default.post(name: .refreshMeetings, object: nil)
                        }
                }

                HStack {
                    Text("Snooze:")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(snoozeMinutes)")
                            .font(.body.monospacedDigit())
                            .fontWeight(.bold)
                        Text(snoozeMinutes == 1 ? "minute" : "minutes")
                    }
                    .foregroundColor(.secondary)

                    Stepper("", value: $snoozeMinutes, in: 1...30, step: 1)
                        .labelsHidden()
                }

                HStack {
                    Text("Notification Sound:")
                    Spacer()
                    Picker("", selection: $selectedSoundName) {
                        ForEach(soundOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    // An explicit width: with .fixedSize() the Form squeezed it to just the arrows.
                    .frame(width: 150)
                    .onChange(of: selectedSoundName) { _, _ in
                        playSelectedSound()  // Preview the newly chosen sound.
                    }
                    
                    Button(action: playSelectedSound) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Play Sound")
                }
            }

            Section(header: sectionHeader("Calendars")) {
                if calendarSelectionViewModel.calendarOptions.isEmpty {
                    Text("No calendars available")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(calendarSelectionViewModel.calendarOptions) { option in
                            calendarToggle(for: option)
                        }
                    }
                }
            }

            Section(header: sectionHeader("Updates")) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { appUpdater.automaticallyChecksForUpdates },
                    set: { appUpdater.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Automatically install updates", isOn: Binding(
                    get: { appUpdater.automaticallyDownloadsUpdates },
                    set: { appUpdater.automaticallyDownloadsUpdates = $0 }
                ))
                .disabled(!appUpdater.automaticallyChecksForUpdates)
                Button("Check for Updates…") {
                    appUpdater.checkForUpdates()
                }
                .disabled(!appUpdater.canCheckForUpdates)
            }

            Section(header: sectionHeader("Application")) {
                let versionLabel: String = {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    if let version, let build, build != version {
                        return "FullscreenReminder v\(version) (\(build))"
                    }
                    if let version {
                        return "FullscreenReminder v\(version)"
                    }
                    return "FullscreenReminder"
                }()
                Text(versionLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 380)
        .alert(
            "Unable to Update Launch at Login", isPresented: $isShowingLaunchAtLoginError,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(launchAtLoginErrorMessage ?? "An unknown error occurred.")
            })
    }

    private func playSelectedSound() {
        previewSound?.stop()

        if let url = ReminderPreferences.soundURL(for: selectedSoundName),
            let sound = NSSound(contentsOf: url, byReference: true)
        {
            previewSound = sound
            if sound.play() == false {
                NSSound.beep()
            }
        } else if let sound = NSSound(named: NSSound.Name(selectedSoundName)) {
            previewSound = sound
            if sound.play() == false {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func calendarToggle(for option: CalendarOption) -> some View {
        Button {
            calendarSelectionViewModel.toggleSelection(for: option.id)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(option.color.flatMap { Color(nsColor: $0) } ?? Color.secondary)
                    .frame(width: 10, height: 10)
                Text(option.name)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(option.isSelected ? .accentColor : .secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
