import Foundation

@MainActor
final class RadioControlViewModel: ObservableObject {
    @Published private(set) var status = RadioDeviceStatus.placeholder

    private let bridge = MHRadioEngineBridge()
    private var pollingTask: Task<Void, Never>?

    deinit {
        pollingTask?.cancel()
    }

    func refresh() {
        status = map(snapshot: bridge.refreshStatus())
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.status = self.map(snapshot: self.bridge.currentStatus())
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func connect(selectedSerial: String?) {
        status = map(snapshot: bridge.connect(toSerialNumber: selectedSerial))
    }

    func disconnect() {
        status = map(snapshot: bridge.disconnectDevice())
    }

    func startRX() {
        status = map(snapshot: bridge.startRX())
    }

    func stopRX() {
        status = map(snapshot: bridge.stopRX())
    }

    func apply(globalSettings: GlobalRadioSettings, bandSession: BandSessionState?) {
        guard let bandSession else { return }
        status = map(
            snapshot: bridge.applyFrequencyHz(
                UInt64(max(0, bandSession.frequencyHz.rounded())),
                sampleRate: globalSettings.sampleRate,
                ampEnabled: globalSettings.ampEnabled,
                lnaGain: Int(globalSettings.lnaGain.rounded()),
                vgaGain: Int(globalSettings.vgaGain.rounded()),
                txVGAGain: Int(globalSettings.txVGAGain.rounded())
            )
        )
    }

    private func map(snapshot: MHRadioStatusSnapshot) -> RadioDeviceStatus {
        let spectrum = snapshot.spectrumBins.map(\.doubleValue)
        let rxRFLevel = spectrum.max() ?? 0
        let rxAudioLevel = min(1, (spectrum.reduce(0, +) / Double(max(spectrum.count, 1))) * 1.4)

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
            rxRFLevel: rxRFLevel,
            rxAudioLevel: rxAudioLevel,
            txRFLevel: state == .transmitting ? 0.15 : 0,
            txAudioLevel: state == .transmitting ? 0.08 : 0
        )
    }
}
