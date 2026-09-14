import SwiftUI

struct SettingsView: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var engine = Engine.shared
    @State private var selection: Binding.ID?

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return store.bindings.firstIndex { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 240)
            detail.frame(minWidth: 320)
        }
        .frame(minWidth: 620, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .status) {
                Toggle("Gestures enabled", isOn: $store.isEnabled).toggleStyle(.switch)
            }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach($store.bindings) { $binding in
                    HStack {
                        Toggle("", isOn: $binding.isEnabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.name.isEmpty ? "Untitled" : binding.name)
                            Text(binding.gesture.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(binding.id)
                }
            }
            Divider()
            HStack(spacing: 4) {
                Button(action: addBinding) { Image(systemName: "plus") }
                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selectedIndex == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func addBinding() {
        let new = Binding(
            name: "New binding",
            gesture: Gesture(fingers: 5),
            action: ActionPreset.fullScreenToClipboard.action
        )
        store.bindings.append(new)
        selection = new.id
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        store.bindings.remove(at: index)
        selection = store.bindings.first?.id
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            BindingEditor(binding: $store.bindings[index])
        } else {
            VStack {
                Spacer()
                Text("Select a binding").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            if let error = engine.startupError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let last = engine.lastGesture {
                Text("Last gesture: \(last.displayName)").foregroundStyle(.secondary)
            } else {
                Text("Waiting for a gesture…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal config") { store.revealConfigInFinder() }
                .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Editor

private struct BindingEditor: View {
    @SwiftUI.Binding var binding: Binding
    @State private var isRecording = false

    var body: some View {
        Form {
            Section("Binding") {
                TextField("Name", text: $binding.name)
            }

            Section("Gesture") {
                Stepper(
                    "Fingers: \(binding.gesture.fingers)",
                    value: $binding.gesture.fingers,
                    in: 2...5
                )
                HStack {
                    Button(isRecording ? "Tap the trackpad…" : "Record gesture") {
                        isRecording ? stopRecording() : startRecording()
                    }
                    if isRecording {
                        Button("Cancel", action: stopRecording)
                        ProgressView().controlSize(.small)
                    }
                }
            }

            Section("Action") {
                Picker("Preset", selection: presetSelection) {
                    Text("Custom").tag(ActionPreset?.none)
                    ForEach(ActionPreset.allCases) { preset in
                        Text(preset.rawValue).tag(ActionPreset?.some(preset))
                    }
                }
                actionFields
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
    }

    // MARK: Recording

    private func startRecording() {
        isRecording = true
        Engine.shared.recordingHandler = { gesture in
            binding.gesture = gesture
            stopRecording()
        }
    }

    private func stopRecording() {
        isRecording = false
        Engine.shared.recordingHandler = nil
    }

    // MARK: Action editing

    private var presetSelection: SwiftUI.Binding<ActionPreset?> {
        SwiftUI.Binding(
            get: { ActionPreset.allCases.first { $0.action == binding.action } },
            set: { if let preset = $0 { binding.action = preset.action } }
        )
    }

    @ViewBuilder
    private var actionFields: some View {
        switch binding.action {
        case .shell(let command, let arguments):
            TextField("Command", text: SwiftUI.Binding(
                get: { command },
                set: { binding.action = .shell(command: $0, arguments: arguments) }
            ))
            TextField("Arguments", text: SwiftUI.Binding(
                get: { arguments.joined(separator: " ") },
                set: {
                    let parts = $0.split(separator: " ").map(String.init)
                    binding.action = .shell(command: command, arguments: parts)
                }
            ))

        case .keyStroke(let keyCode, let modifiers):
            TextField("Key code", value: SwiftUI.Binding(
                get: { Int(keyCode) },
                set: { binding.action = .keyStroke(keyCode: CGKeyCode($0), modifiers: modifiers) }
            ), format: .number)
            HStack {
                ForEach(Action.Modifier.allCases, id: \.self) { modifier in
                    Toggle(modifier.symbol, isOn: SwiftUI.Binding(
                        get: { modifiers.contains(modifier) },
                        set: { isOn in
                            var updated = Set(modifiers)
                            if isOn { updated.insert(modifier) } else { updated.remove(modifier) }
                            binding.action = .keyStroke(
                                keyCode: keyCode,
                                modifiers: Action.Modifier.allCases.filter(updated.contains)
                            )
                        }
                    ))
                    .toggleStyle(.button)
                }
            }
        }
    }
}
