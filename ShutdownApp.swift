import SwiftUI
import ServiceManagement

@main
struct ShutdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchAtLogin = UserDefaults.standard.object(forKey: "LaunchAtLogin") as? Bool ?? true
        if launchAtLogin && SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to register launch at login: \(error)")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let customIcon = NSImage(named: "AppIcon") {
                customIcon.size = NSSize(width: 16, height: 16)
                customIcon.isTemplate = false
                button.image = customIcon
            } else {
                button.image = NSImage(systemSymbolName: "power.circle", accessibilityDescription: "Shutdown Controller")
            }
            button.action = #selector(togglePopover)
        }

        popover.contentSize = NSSize(width: 280, height: 350)
        popover.behavior = .semitransient
        popover.contentViewController = NSHostingController(rootView: ContentView())
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
