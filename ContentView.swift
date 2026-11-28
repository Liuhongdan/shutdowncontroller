import SwiftUI
import ServiceManagement
import AppKit
import Darwin

class ShutdownManager: NSObject, ObservableObject {
    @Published private(set) var currentTime = Date()
    @Published private(set) var controlMode: ShutdownControlMode = .app {
        didSet {
            saveControlMode()
            syncLaunchAgent()
        }
    }
    @Published private(set) var isRequestingSystemEventsPermission = false
    @Published private(set) var systemEventsPermissionError: String?
    @Published var slots: [ShutdownSlot] = [
        ShutdownSlot(hour: 22, minute: 35, isEnabled: false),
        ShutdownSlot(hour: 22, minute: 40, isEnabled: false),
        ShutdownSlot(hour: 22, minute: 45, isEnabled: false)
    ] {
        didSet {
            saveSlots()
            syncLaunchAgent()
        }
    }
    
    private var timer: Timer?
    private var warningPanel: NSPanel?
    private let saveKey = "SavedShutdownSlots"
    private let controlModeKey = "ShutdownControlMode"

    override init() {
        super.init()
        loadSlots()
        loadControlMode()
        startTimer()
        syncLaunchAgent()
        if controlMode == .system {
            requestSystemEventsPermission()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func canAddSlot(hour: Int, minute: Int) -> Bool {
        slots.count < 5 && !ScheduleRules.hasDuplicate(hour: hour, minute: minute, in: slots)
    }

    @discardableResult
    func addSlot(_ slot: ShutdownSlot) -> Bool {
        guard canAddSlot(hour: slot.hour, minute: slot.minute) else { return false }
        slots.append(slot)
        sortSlots()
        return true
    }

    func removeSlot(id: UUID) {
        guard let slot = slots.first(where: { $0.id == id }), !isSlotLocked(slot) else { return }
        slots.removeAll { $0.id == id }
        sortSlots()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }),
              !isSlotLocked(slots[index]) else {
            return
        }
        slots[index].isEnabled = isEnabled
    }

    func isSlotLocked(_ slot: ShutdownSlot) -> Bool {
        ScheduleRules.isLocked(slot, at: Date())
    }

    func isControlModeLocked() -> Bool {
        slots.contains { isSlotLocked($0) }
    }

    func setControlMode(_ mode: ShutdownControlMode) {
        guard !isControlModeLocked(),
              !isRequestingSystemEventsPermission,
              mode != controlMode else {
            return
        }

        guard mode == .system else {
            systemEventsPermissionError = nil
            controlMode = mode
            return
        }

        requestSystemEventsPermission()
    }

    private func requestSystemEventsPermission() {
        guard !isRequestingSystemEventsPermission else { return }
        isRequestingSystemEventsPermission = true
        systemEventsPermissionError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = NSAppleScript(
                source: "tell application id \"com.apple.systemevents\" to get name"
            )
            var errorInfo: NSDictionary?
            let result = script?.executeAndReturnError(&errorInfo)
            let errorMessage = errorInfo?[NSAppleScript.errorMessage] as? String

            DispatchQueue.main.async {
                guard let self else { return }
                self.isRequestingSystemEventsPermission = false

                if result != nil {
                    self.controlMode = .system
                } else {
                    self.systemEventsPermissionError =
                        "Could not authorize System Events. Allow Shutdown Controller in System Settings > Privacy & Security > Automation, then try again."
                    if self.controlMode == .system {
                        self.controlMode = .app
                    }
                    if let errorMessage {
                        print("System Events permission request failed: \(errorMessage)")
                    }
                }
            }
        }
    }

    private static func slotComesBefore(_ lhs: ShutdownSlot, _ rhs: ShutdownSlot) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        return lhs.minute < rhs.minute
    }

    private func sortSlots() {
        slots.sort(by: Self.slotComesBefore)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkSchedules()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func checkSchedules() {
        let calendar = Calendar.current
        let now = Date()
        currentTime = now

        for slot in slots where slot.isEnabled {
            guard let scheduledTime = calendar.date(
                bySettingHour: slot.hour,
                minute: slot.minute,
                second: 0,
                of: now
            ) else { continue }

            let occurrence = calendar.startOfDay(for: scheduledTime)
            let warningKey = "LastShutdownWarning-\(slot.id.uuidString)"
            let shutdownKey = "LastShutdown-\(slot.id.uuidString)"

            if now >= scheduledTime.addingTimeInterval(-120), now < scheduledTime,
               !wasHandled(warningKey, on: occurrence) {
                markHandled(warningKey, on: occurrence)
                showShutdownWarning()
            }

            if now >= scheduledTime, now < scheduledTime.addingTimeInterval(60),
               !wasHandled(shutdownKey, on: occurrence) {
                markHandled(shutdownKey, on: occurrence)
                if controlMode == .app {
                    executeShutdown()
                }
            }
        }
    }

    private func wasHandled(_ key: String, on occurrence: Date) -> Bool {
        UserDefaults.standard.object(forKey: key) != nil &&
            UserDefaults.standard.double(forKey: key) == occurrence.timeIntervalSince1970
    }

    private func markHandled(_ key: String, on occurrence: Date) {
        UserDefaults.standard.set(occurrence.timeIntervalSince1970, forKey: key)
    }

    private func showShutdownWarning() {
        guard warningPanel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shutdown Controller"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let heading = NSTextField(labelWithString: "Shutdown in 2 minutes")
        heading.font = .boldSystemFont(ofSize: 15)
        let message = NSTextField(wrappingLabelWithString: "Please save your work and prepare for the scheduled shutdown.")
        let okButton = NSButton(title: "OK", target: self, action: #selector(dismissShutdownWarning))
        okButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [heading, message, okButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        panel.contentView = stack
        panel.setContentSize(NSSize(width: 360, height: 150))
        panel.center()
        warningPanel = panel
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func dismissShutdownWarning() {
        warningPanel?.orderOut(nil)
        warningPanel = nil
    }

    func executeShutdown() {
        Self.executeShutdownRequest()
    }

    static func executeShutdownRequest() {
        let script = NSAppleScript(
            source: "tell application id \"com.apple.systemevents\" to shut down"
        )
        var errorInfo: NSDictionary?
        guard script?.executeAndReturnError(&errorInfo) != nil else {
            let errorMessage = errorInfo?[NSAppleScript.errorMessage] as? String
                ?? "Unknown AppleScript error"
            print("Failed to execute shutdown request: \(errorMessage)")
            return
        }
    }

    private func saveSlots() {
        if let encoded = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }

    private func saveControlMode() {
        UserDefaults.standard.set(controlMode.rawValue, forKey: controlModeKey)
    }

    private func loadControlMode() {
        if let rawValue = UserDefaults.standard.string(forKey: controlModeKey),
           let mode = ShutdownControlMode(rawValue: rawValue) {
            controlMode = mode
        }
    }

    private func syncLaunchAgent() {
        let label = "com.local.ShutdownController"
        let launchAgentsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory.appendingPathComponent("\(label).plist")
        let uid = getuid()

        runLaunchctl(["bootout", "gui/\(uid)/\(label)"])

        guard controlMode == .system else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }

        let enabledSlots = slots.filter(\.isEnabled)
        guard !enabledSlots.isEmpty else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }

        guard let executablePath = Bundle.main.executableURL?.path else {
            print("Failed to sync shutdown LaunchAgent: app executable path is unavailable")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )

            let calendarIntervals = enabledSlots.map {
                [
                    "Hour": $0.hour,
                    "Minute": $0.minute
                ]
            }
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [
                    executablePath,
                    "--scheduled-shutdown"
                ],
                "RunAtLoad": false,
                "StartCalendarInterval": calendarIntervals
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
            runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        } catch {
            print("Failed to sync shutdown LaunchAgent: \(error)")
        }
    }

    private func runLaunchctl(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to run launchctl: \(error)")
        }
    }

    private func loadSlots() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ShutdownSlot].self, from: data) {
            slots = decoded.sorted(by: Self.slotComesBefore)
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = ShutdownManager()
    @State private var newHour: Int = 22
    @State private var newMinute: Int = 0
    @AppStorage("LaunchAtLogin") private var launchAtLogin = true
    @State private var launchAtLoginError: String?
    @State private var showingAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shutdown Controller")
                .font(.headline)
            
            Divider()

            List {
                ForEach($manager.slots) { $slot in
                    let isLocked = manager.isSlotLocked(slot)
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { slot.isEnabled },
                            set: { manager.setEnabled($0, for: slot.id) }
                        ))
                            .labelsHidden()
                        
                        Text(String(format: "%02d:%02d", slot.hour, slot.minute))
                            .font(.system(.body, design: .monospaced))
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            manager.removeSlot(id: slot.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .disabled(isLocked)
                    .opacity(isLocked ? 0.5 : 1)
                }
            }
            .frame(height: 150)

            HStack(spacing: 8) {
                Picker("Hour", selection: $newHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                .frame(width: 70)
                .labelsHidden()
                
                Text(":")
                
                Picker("Minute", selection: $newMinute) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .frame(width: 70)
                .labelsHidden()
                
                Button("Add Slot") {
                    manager.addSlot(ShutdownSlot(hour: newHour, minute: newMinute, isEnabled: true))
                }
                .disabled(!manager.canAddSlot(hour: newHour, minute: newMinute))
            }

            Divider()

            HStack {
                Text("\(manager.slots.filter { $0.isEnabled }.count) active schedule(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("About") {
                    showingAbout = true
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Shutdown control")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Shutdown control", selection: Binding(
                    get: { manager.controlMode },
                    set: { manager.setControlMode($0) }
                )) {
                    ForEach(ShutdownControlMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(manager.isControlModeLocked() || manager.isRequestingSystemEventsPermission)

                if manager.isControlModeLocked() {
                    Text("Locked within 2 hours of an enabled shutdown.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if manager.isRequestingSystemEventsPermission {
                    Text("Waiting for System Events permission.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let permissionError = manager.systemEventsPermissionError {
                    Text(permissionError)
                        .font(.caption2)
                        .foregroundColor(.red)
                } else if manager.controlMode == .app {
                    Text("Schedules stop working after you quit the app.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Schedules continue through macOS after you quit.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    updateLaunchAtLogin(enabled)
                }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 280, height: 430)
        .onAppear {
            updateLaunchAtLogin(launchAtLogin)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                guard service.status != .enabled else { return }
                try service.register()
            } else {
                guard service.status == .enabled || service.status == .requiresApproval else { return }
                try service.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not update login setting: \(error.localizedDescription)"
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.1"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Shutdown Controller")
                            .font(.title2.weight(.semibold))
                        Text("Version \(appVersion) (Build \(buildNumber))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Schedule automatic shutdowns on macOS.")
                            .font(.callout)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Contributor")
                        .font(.headline)
                    Text("Liuhongdan")

                    Link("Project Repository", destination: URL(string: "https://github.com/Liuhongdan/shutdowncontroller")!)
                    Link("Report an Issue", destination: URL(string: "https://github.com/Liuhongdan/shutdowncontroller/issues")!)
                    Link("Releases", destination: URL(string: "https://github.com/Liuhongdan/shutdowncontroller/releases")!)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("License")
                        .font(.headline)
                    Text("MIT License")
                    Text("Copyright © 2026 Liuhongdan")
                        .foregroundColor(.secondary)
                    Link("View License", destination: URL(string: "https://github.com/Liuhongdan/shutdowncontroller/blob/main/LICENSE")!)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Third-Party Notices")
                        .font(.headline)
                    Text("No third-party software libraries are bundled. This app uses Apple SwiftUI, AppKit, and ServiceManagement frameworks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
        }
        .frame(width: 420, height: 390)
    }
}
