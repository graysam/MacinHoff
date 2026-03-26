import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @EnvironmentObject private var radioModel: RadioControlViewModel
    @State private var inputDevices: [String] = []
    @State private var outputDevices: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusCard(title: "HackRF", accent: .mint) {
                    Text(radioModel.status.connectionSummary)
                        .font(.headline)
                    Text("libhackrf \(radioModel.status.libraryVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let lastError = radioModel.status.lastError {
                        Text(lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Text("Transport")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(radioModel.status.transportState.title)
                    }
                }

                StatusCard(title: "Global Controls", accent: .orange) {
                    Picker("Region", selection: Binding(
                        get: { appModel.regionPreset },
                        set: { appModel.setRegionPreset($0) }
                    )) {
                        ForEach(RegionPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                    LabeledContent("Snap") {
                        Stepper(value: appModel.bindingForGlobal(\.snapStepHz), in: 100...25_000, step: 100) {
                            Text(FrequencyFormatting.compactString(for: appModel.globalSettings.snapStepHz))
                        }
                    }

                    LabeledContent("LNA") {
                        Slider(value: appModel.bindingForGlobal(\.lnaGain), in: 0...40, step: 8)
                    }
                    Text("\(Int(appModel.globalSettings.lnaGain)) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("VGA") {
                        Slider(value: appModel.bindingForGlobal(\.vgaGain), in: 0...62, step: 2)
                    }
                    Text("\(Int(appModel.globalSettings.vgaGain)) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("TX VGA") {
                        Slider(value: appModel.bindingForGlobal(\.txVGAGain), in: 0...47, step: 1)
                    }
                    Text("\(Int(appModel.globalSettings.txVGAGain)) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("AMP", isOn: appModel.bindingForGlobal(\.ampEnabled))

                    Picker("Audio In", selection: appModel.bindingForGlobal(\.audioInputName)) {
                        ForEach(deviceOptions(current: appModel.globalSettings.audioInputName, available: inputDevices), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }

                    Picker("Audio Out", selection: appModel.bindingForGlobal(\.audioOutputName)) {
                        ForEach(deviceOptions(current: appModel.globalSettings.audioOutputName, available: outputDevices), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }

                    Button("Refresh Audio Devices") {
                        refreshAudioDevices()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            refreshAudioDevices()
        }
    }

    private func deviceOptions(current: String, available: [String]) -> [String] {
        var options = ["System Default"] + available
        if current != "System Default", !options.contains(current) {
            options.append(current)
        }
        return options
    }

    private func refreshAudioDevices() {
        inputDevices = AudioDeviceService.deviceNames(for: .input)
        outputDevices = AudioDeviceService.deviceNames(for: .output)
    }
}
