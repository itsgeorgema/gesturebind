import AppKit
import SwiftUI

/// Menu-bar-only agent: no Dock icon, no main window until Settings is opened.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = Store.shared   // seeds bindings.json on first launch
        Engine.shared.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "hand.point.up.left.fill",
            accessibilityDescription: "GestureBind"
        )
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(
            title: "Gestures Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.tag = 1
        menu.addItem(toggle)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.tag = 2
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit GestureBind", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleEnabled() {
        Store.shared.isEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.shared.toggle()
        if let error = LoginItem.shared.lastError { presentError(error) }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Launch at Login"
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "GestureBind Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.state = Store.shared.isEnabled ? .on : .off
        // The user can revoke the login item in System Settings at any time,
        // so re-read the real status each time the menu opens.
        LoginItem.shared.refresh()
        menu.item(withTag: 2)?.state = LoginItem.shared.isEnabled ? .on : .off
    }
}

// Headless control of the login item, so it can be scripted or tested without
// opening the menu: `GestureBind.app/Contents/MacOS/GestureBind --login-item on|off|status`
if let flagIndex = CommandLine.arguments.firstIndex(of: "--login-item") {
    let argument = CommandLine.arguments.indices.contains(flagIndex + 1)
        ? CommandLine.arguments[flagIndex + 1]
        : "status"
    switch argument {
    case "on":  LoginItem.shared.setEnabled(true)
    case "off": LoginItem.shared.setEnabled(false)
    default:    LoginItem.shared.refresh()
    }
    if let error = LoginItem.shared.lastError {
        FileHandle.standardError.write((error + "\n").data(using: .utf8)!)
        exit(1)
    }
    print("launch at login: \(LoginItem.shared.isEnabled ? "enabled" : "disabled")")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
