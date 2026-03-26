import Foundation

@MainActor
final class RadioControlViewModel: ObservableObject {
    @Published private(set) var status = RadioDeviceStatus.placeholder

    private let bridge: MHRadioEngineBridge
    private let audioOutput: AudioOutputService
    private var pollingTask: Task<Void, Never>?
    private var selectedAudioOutputName = "System Default"

    init() {
        let bridge = MHRadioEngineBridge()
        self.bridge = bridge
        self.audioOutput = AudioOutputService { maxSamples in
            let data = bridge.consumeRXAudioSamples(maxSamples)
            guard !data.isEmpty else { return [] }
            return data.withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Float.self))
            }
        }
    }

    func refresh() {
        updateStatus(with: bridge.refreshStatus())
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateStatus(with: self.bridge.currentStatus())
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func connect(selectedSerial: String?) {
        updateStatus(with: bridge.connect(toSerialNumber: selectedSerial))
    }

    func disconnect() {
        updateStatus(with: bridge.disconnectDevice())
    }

    func startRX() {
        updateStatus(with: bridge.startRX())
    }

    func stopRX() {
        updateStatus(with: bridge.stopRX())
    }

    func apply(globalSettings: GlobalRadioSettings, bandSession: BandSessionState?) {
        guard let bandSession else { return }
        selectedAudioOutputName = globalSettings.audioOutputName
        updateStatus(
            with: bridge.applyFrequencyHz(
                UInt64(max(0, bandSession.frequencyHz.rounded())),
                sampleRate: globalSettings.sampleRate,
                ampEnabled: globalSettings.ampEnabled,
                lnaGain: Int(globalSettings.lnaGain.rounded()),
                vgaGain: Int(globalSettings.vgaGain.rounded()),
                txVGAGain: Int(globalSettings.txVGAGain.rounded()),
                mode: bandSession.mode.rawValue,
                rxFilterHz: bandSession.rxFilterHz
            )
        )
    }

    private func updateStatus(with snapshot: MHRadioStatusSnapshot) {
        status = map(snapshot: snapshot)
        audioOutput.update(
            shouldPlay: status.transportState == .receiving,
            outputDeviceName: selectedAudioOutputName
        )
    }

    private func map(snapshot: MHRadioStatusSnapshot) -> RadioDeviceStatus {
        let spectrum = snapshot.spectrumBins.map(\.doubleValue)

        let devices = snapshot.devices.map {
            HackRFDevice(
                serialNumber: $0.serialNumber,
                boardName: $0.boardName,
                displayName: $0.displayName,
                firmwareVersion: $0.firmwareVersion,
                usbAPIVersion: $0.usbAPIVersion,
                sharedUSBDeviceCount: $0.sharedUSBDeviceCount
            )
        }

        let state: RadioTransportState
        switch snapshot.transportState {
        case .idle:
            state = .idle
        case .receiving:
            state = .receiving
        case .transmitting:
            state = .transmitting
        case .fault:
            state = .fault
        @unknown default:
            state = .fault
        }

        return RadioDeviceStatus(
            devices: devices,
            libraryVersion: snapshot.libraryVersion,
            connectedSerialNumber: snapshot.connectedSerialNumber,
            connectionSummary: snapshot.connectionSummary,
            lastError: snapshot.lastError,
            transportState: state,
            spectrumBins: spectrum,
            tunedFrequencyHz: Double(snapshot.tunedFrequencyHz),
            sampleRate: snapshot.sampleRate,
            rxRFLevel: Double(snapshot.rxRFLevel),
            rxAudioLevel: Double(snapshot.rxAudioLevel),
            txRFLevel: Double(snapshot.txRFLevel),
            txAudioLevel: Double(snapshot.txAudioLevel)
        )
    }
}
