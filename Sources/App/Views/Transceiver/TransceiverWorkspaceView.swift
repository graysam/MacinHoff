import SwiftUI

struct TransceiverWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @EnvironmentObject private var radioModel: RadioControlViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            deviceStrip
            BandTabsView()

            if let band = appModel.selectedBandDefinition,
               let session = appModel.selectedBandSession {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        meterCluster(title: "TX", audioLevel: radioModel.status.txAudioLevel, rfLevel: radioModel.status.txRFLevel, rfBaseColor: .cyan)
                        txSection(session: session)
                        globalSection(band: band, session: session)
                        rxSection(session: session)
                        meterCluster(title: "RX", audioLevel: radioModel.status.rxAudioLevel, rfLevel: radioModel.status.rxRFLevel, rfBaseColor: .cyan)
                    }
                    .frame(minHeight: 320, maxHeight: 320)

                    SpectrumWaterfallView(
                        centerFrequencyHz: session.frequencyHz,
                        spanHz: session.visibleSpanHz,
                        spectrumBins: radioModel.status.spectrumBins,
                        palette: appModel.globalSettings.waterfallPalette
                    ) { requestedFrequency in
                        appModel.tuneSelectedBand(to: requestedFrequency)
                    } onPanRequest: { deltaHz in
                        appModel.panSelectedBand(by: deltaHz)
                    } onZoomRequest: { factor in
                        appModel.zoomSelectedBand(by: factor)
                    }
                    .frame(minHeight: 380)
                }
                .padding(.top, 6)
            } else {
                ContentUnavailableView("No Band Selected", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    Color(red: 0.15, green: 0.18, blue: 0.2),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private var deviceStrip: some View {
        HStack(spacing: 12) {
            Picker("", selection: appModel.bindingForGlobal(\.selectedDeviceSerial)) {
                Text("First available").tag(String?.none)
                ForEach(radioModel.status.devices) { device in
                    Text("\(device.displayName) • \(device.boardName)").tag(Optional(device.serialNumber))
                }
            }
            .frame(maxWidth: 360)
            .labelsHidden()

            Picker("", selection: appModel.sampleRateBinding) {
                ForEach(SampleRateOption.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .frame(width: 140)
            .labelsHidden()
            .disabled(radioModel.isRFRunning)

            Button(radioModel.isRFRunning ? "Stop RF" : "Start RF") {
                if radioModel.isRFRunning {
                    radioModel.stopRF()
                } else {
                    radioModel.startRF(
                        globalSettings: appModel.globalSettings,
                        bandSession: appModel.selectedBandSession
                    )
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Pop Out") {
                openWindow(id: "waterfall")
            }

            Spacer()

            Text(radioModel.status.connectionSummary)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func meterCluster(title: String, audioLevel: Double, rfLevel: Double, rfBaseColor: Color) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 8) {
                SegmentedLevelMeterView(title: "AUDIO", baseColor: .green, level: audioLevel)
                SegmentedLevelMeterView(title: "RF", baseColor: rfBaseColor, level: rfLevel)
            }
        }
        .frame(width: 112)
        .frame(maxHeight: .infinity)
    }

    private func txSection(session: BandSessionState) -> some View {
        BandControlSection(title: "TX", tint: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Offset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: appModel.bindingForSelectedBand(\.txOffsetHz, fallback: session.txOffsetHz), in: -25_000...25_000, step: 100) {
                    Text(FrequencyFormatting.compactString(for: session.txOffsetHz))
                }

                Text("Filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: appModel.bindingForSelectedBand(\.txFilterHz, fallback: session.txFilterHz), in: 300...12_000, step: 100) {
                    Text(FrequencyFormatting.compactString(for: session.txFilterHz))
                }

                Toggle("Split", isOn: appModel.bindingForSelectedBand(\.splitEnabled, fallback: session.splitEnabled))
                Toggle("Monitor", isOn: appModel.bindingForSelectedBand(\.monitorEnabled, fallback: session.monitorEnabled))
                Toggle("TX Arm", isOn: appModel.bindingForSelectedBand(\.txArmed, fallback: session.txArmed))

                Spacer(minLength: 0)
            }
        }
        .disabled(!radioModel.txUnlocked)
        .opacity(radioModel.txUnlocked ? 1 : 0.55)
    }

    private func globalSection(band: BandDefinition, session: BandSessionState) -> some View {
        BandControlSection(title: "GLOBAL", tint: .teal) {
            VStack(alignment: .leading, spacing: 14) {
                VFOReadoutView(
                    frequencyHz: appModel.bindingForSelectedBand(\.frequencyHz, fallback: session.frequencyHz),
                    stepForward: { appModel.stepSelectedBand(by: 1) },
                    stepBackward: { appModel.stepSelectedBand(by: -1) }
                )

                Picker("Mode", selection: appModel.bindingForSelectedBand(\.mode, fallback: session.mode)) {
                    ForEach(OperatingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Span")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(FrequencyFormatting.compactString(for: session.visibleSpanHz))
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper(value: appModel.bindingForSelectedBand(\.stepHz, fallback: session.stepHz), in: 10...50_000, step: 10) {
                            Text(FrequencyFormatting.compactString(for: session.stepHz))
                        }
                    }
                }

                if band.isUnlocked {
                    Text("Unlocked tuning with no band clamp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(band.name) • \(FrequencyFormatting.compactString(for: band.lowerHz)) to \(FrequencyFormatting.compactString(for: band.upperHz))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    StatBadge(title: "Tune", value: FrequencyFormatting.displayString(for: radioModel.status.tunedFrequencyHz))
                    StatBadge(title: "Rate", value: FrequencyFormatting.compactString(for: radioModel.status.sampleRate))
                }

                Button("Reset Tab") {
                    appModel.resetSelectedBand()
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func rxSection(session: BandSessionState) -> some View {
        BandControlSection(title: "RX", tint: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: appModel.bindingForSelectedBand(\.rxFilterHz, fallback: session.rxFilterHz), in: 300...12_000, step: 100) {
                    Text(FrequencyFormatting.compactString(for: session.rxFilterHz))
                }

                Text("Squelch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: appModel.bindingForSelectedBand(\.squelch, fallback: session.squelch), in: 0...100, step: 1)
                Text("\(Int(session.squelch))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("AGC", isOn: appModel.bindingForSelectedBand(\.agcEnabled, fallback: session.agcEnabled))

                HStack {
                    StatBadge(title: "Transport", value: radioModel.status.transportState.title)
                    StatBadge(title: "Radio", value: radioModel.status.connectedSerialNumber ?? "None")
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct StatBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.15))
        )
    }
}
