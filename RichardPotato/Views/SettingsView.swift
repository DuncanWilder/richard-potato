import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: AppController

    private static let systemDefaultTag = "system-default"

    var body: some View {
        Form {
            Section("Settings") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    Text(controller.store.shortcut.displayName)
                        .font(.body.monospaced())
                    Button(controller.store.isRecording ? "Press a key…" : "Change…") {
                        controller.store.isRecording.toggle()
                    }
                }

                Picker("Activation", selection: activationBinding) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Insert with", selection: insertionBinding) {
                    ForEach(InsertionMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }

                if controller.store.insertionMethod == .paste {
                    Toggle("Refine transcript before pasting", isOn: postProcessBinding)
                }

                Picker("Input device", selection: microphoneBinding) {
                    Text("System default").tag(Self.systemDefaultTag)
                    ForEach(controller.engine.inputDevices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }

                Toggle("Show dictation bar", isOn: indicatorBinding)
            }

            Section("Custom corrections") {
                if !controller.store.corrections.isEmpty {
                    HStack(spacing: 8) {
                        Text("Heard phrase")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 16, height: 1)
                        Text("Write as")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 22, height: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(controller.store.corrections) { correction in
                    HStack(spacing: 8) {
                        TextField("", text: correctionBinding(correction.id, keyPath: \.heard))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .multilineTextAlignment(strategy: .layoutBased)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.background, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                            .accessibilityLabel("Heard phrase")
                        Image(systemName: "arrow.right")
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        TextField("", text: correctionBinding(correction.id, keyPath: \.written))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.leading)
                            .multilineTextAlignment(strategy: .layoutBased)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.background, in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                            .accessibilityLabel("Write as")
                        Button {
                            controller.store.corrections.removeAll { $0.id == correction.id }
                            controller.store.save()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .frame(width: 22)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove correction")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button("Add correction") {
                        controller.store.corrections.append(TextCorrection(heard: "", written: ""))
                        controller.store.save()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            controller.refreshPermissions()
        }
        .onDisappear {
            controller.store.isRecording = false
        }
        .onExitCommand {
            controller.store.isRecording = false
        }
    }

    private var activationBinding: Binding<ActivationMode> {
        Binding(
            get: { controller.store.activationMode },
            set: { mode in
                controller.store.activationMode = mode
                controller.store.save()
            }
        )
    }

    private var insertionBinding: Binding<InsertionMethod> {
        Binding(
            get: { controller.store.insertionMethod },
            set: { method in
                controller.store.insertionMethod = method
                controller.store.save()
            }
        )
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { controller.store.microphoneUID ?? Self.systemDefaultTag },
            set: { uid in
                controller.selectMicrophone(uid: uid == Self.systemDefaultTag ? nil : uid)
            }
        )
    }

    private var postProcessBinding: Binding<Bool> {
        Binding(
            get: { controller.store.postProcessTranscript },
            set: { enabled in
                controller.store.postProcessTranscript = enabled
                controller.store.save()
            }
        )
    }

    private var indicatorBinding: Binding<Bool> {
        Binding(
            get: { controller.store.showListeningIndicator },
            set: { controller.setListeningIndicatorVisible($0) }
        )
    }

    private func correctionBinding(_ id: UUID, keyPath: WritableKeyPath<TextCorrection, String>) -> Binding<String> {
        Binding(
            get: { controller.store.corrections.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                guard let index = controller.store.corrections.firstIndex(where: { $0.id == id }) else { return }
                controller.store.corrections[index][keyPath: keyPath] = value
                controller.store.save()
            }
        )
    }
}
