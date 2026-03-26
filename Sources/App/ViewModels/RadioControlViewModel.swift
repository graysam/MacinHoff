import Foundation

extension MHRadioEngineBridge: @unchecked Sendable {}
extension MHHackRFDeviceSnapshot: @unchecked Sendable {}
extension MHRadioStatusSnapshot: @unchecked Sendable {}

private struct RadioApplyRequest: Sendable {
    let frequencyHz: UInt64
    let sampleRate: Double
    let ampEnabled: Bool
    let lnaGain: Int
    let vgaGain: Int
    let txVGAGain: Int
    let mode: String
    let rxFilterHz: Double
}

private struct RadioStartRFRequest: Sendable {
    let selectedSerial: String?
    let applyRequest: RadioApplyRequest
}

private actor RadioEngineWorker {
    private let bridge: MHRadioEngineBridge

    init(bridge: MHRadioEngineBridge) {
        self.bridge = bridge
    }

    func refreshStatus() -> MHRadioStatusSnapshot {
        bridge.refreshStatus()
    }

    func currentStatus() -> MHRadioStatusSnapshot {
        bridge.currentStatus()
    }

    func connect(selectedSerial: String?) -> MHRadioStatusSnapshot {
        bridge.connect(toSerialNumber: selectedSerial)
    }

    func disconnect() -> MHRadioStatusSnapshot {
        bridge.disconnectDevice()
    }

    func startRX() -> MHRadioStatusSnapshot {
        bridge.startRX()
    }

    func stopRX() -> MHRadioStatusSnapshot {
        bridge.stopRX()
    }

    func apply(_ request: RadioApplyRequest) -> MHRadioStatusSnapshot {
        bridge.applyFrequencyHz(
            request.frequencyHz,
            sampleRate: request.sampleRate,
            ampEnabled: request.ampEnabled,
            lnaGain: request.lnaGain,
            vgaGain: request.vgaGain,
            txVGAGain: request.txVGAGain,
            mode: request.mode,
            rxFilterHz: request.rxFilterHz
        )
    }

    func startRF(_ request: RadioStartRFRequest) -> MHRadioStatusSnapshot {
        var snapshot = bridge.refreshStatus()
        let connectedSerial = snapshot.connectedSerialNumber
        let needsReconnect: Bool

        if let selectedSerial = request.selectedSerial, !selectedSerial.isEmpty {
            needsReconnect = connectedSerial != selectedSerial
        } else {
            needsReconnect = connectedSerial == nil
        }

        if needsReconnect {
            snapshot = bridge.connect(toSerialNumber: request.selectedSerial)
        }

        guard snapshot.connectedSerialNumber != nil else {
            return snapshot
        }

        snapshot = apply(request.applyRequest)
        guard snapshot.lastError == nil else {
            return snapshot
        }

        return bridge.startRX()
    }

    func stopRF() -> MHRadioStatusSnapshot {
        var snapshot = bridge.currentStatus()
        if snapshot.transportState == .receiving || snapshot.transportState == .transmitting {
            snapshot = bridge.stopRX()
        }
        if snapshot.connectedSerialNumber != nil {
            snapshot = bridge.disconnectDevice()
        }
        return snapshot
    }
}

private func makeRXSampleProvider(for bridge: MHRadioEngineBridge) -> @Sendable (Int) -> [Float] {
    { maxSamples in
        let data = bridge.consumeRXAudioSamples(maxSamples)
        guard !data.isEmpty else { return [] }
        return data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }
}

@MainActor
final class RadioControlViewModel: ObservableObject {
    @Published private(set) var status = RadioDeviceStatus.placeholder

    private let bridge: MHRadioEngineBridge
    private let worker: RadioEngineWorker
    private let audioOutput: AudioOutputService
    private var pollingTask: Task<Void, Never>?
    private var pendingApplyTask: Task<Void, Never>?
    private var applySequence = 0
    private var selectedAudioOutputName = "System Default"

    init() {
        let bridge = MHRadioEngineBridge()
        self.bridge = bridge
        self.worker = RadioEngineWorker(bridge: bridge)
        self.audioOutput = AudioOutputService(sampleProvider: makeRXSampleProvider(for: bridge))
    }

    deinit {
        pollingTask?.cancel()
        pendingApplyTask?.cancel()
    }

    func refresh() {
        invalidatePendingApply()
        performOperation { worker in
            await worker.refreshStatus()
        }
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        let worker = self.worker
        pollingTask = Task { [weak self, worker] in
            while !Task.isCancelled {
                let snapshot = await worker.currentStatus()
                await MainActor.run {
                    guard let self else { return }
                    self.updateStatus(with: snapshot)
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func connect(selectedSerial: String?) {
        invalidatePendingApply()
        performOperation { worker in
            await worker.connect(selectedSerial: selectedSerial)
        }
    }

    func disconnect() {
        invalidatePendingApply()
        performOperation { worker in
            await worker.disconnect()
        }
    }

    func startRX() {
        invalidatePendingApply()
        performOperation { worker in
            await worker.startRX()
        }
    }

    func stopRX() {
        invalidatePendingApply()
        performOperation { worker in
            await worker.stopRX()
        }
    }

    var isRFRunning: Bool {
        status.transportState == .receiving || status.transportState == .transmitting
    }

    var txUnlocked: Bool {
        isRFRunning && status.connectedSerialNumber != nil
    }

    func startRF(globalSettings: GlobalRadioSettings, bandSession: BandSessionState?) {
        guard let bandSession else { return }
        invalidatePendingApply()
        selectedAudioOutputName = globalSettings.audioOutputName
        let request = RadioStartRFRequest(
            selectedSerial: resolvedSelectedSerial(from: globalSettings.selectedDeviceSerial),
            applyRequest: makeApplyRequest(globalSettings: globalSettings, bandSession: bandSession)
        )
        performOperation { worker in
            await worker.startRF(request)
        }
    }

    func stopRF() {
        invalidatePendingApply()
        performOperation { worker in
            await worker.stopRF()
        }
    }

    func apply(globalSettings: GlobalRadioSettings, bandSession: BandSessionState?) {
        guard let bandSession else { return }
        selectedAudioOutputName = globalSettings.audioOutputName
        let request = makeApplyRequest(globalSettings: globalSettings, bandSession: bandSession)
        scheduleApply(request)
    }

    private func updateStatus(with snapshot: MHRadioStatusSnapshot) {
        status = map(snapshot: snapshot)
        audioOutput.update(
            shouldPlay: status.transportState == .receiving,
            outputDeviceName: selectedAudioOutputName
        )
    }

    private func invalidatePendingApply() {
        applySequence += 1
        pendingApplyTask?.cancel()
        pendingApplyTask = nil
    }

    private func scheduleApply(_ request: RadioApplyRequest) {
        applySequence += 1
        let sequence = applySequence
        let worker = self.worker

        pendingApplyTask?.cancel()
        pendingApplyTask = Task { [weak self, worker] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }

            let snapshot = await worker.apply(request)
            await MainActor.run {
                guard let self else { return }
                guard self.applySequence == sequence else { return }
                self.pendingApplyTask = nil
                self.updateStatus(with: snapshot)
            }
        }
    }

    private func performOperation(_ operation: @escaping @Sendable (RadioEngineWorker) async -> MHRadioStatusSnapshot) {
        let worker = self.worker
        Task { [weak self, worker] in
            let snapshot = await operation(worker)
            await MainActor.run {
                guard let self else { return }
                self.updateStatus(with: snapshot)
            }
        }
    }

    private func makeApplyRequest(globalSettings: GlobalRadioSettings, bandSession: BandSessionState) -> RadioApplyRequest {
        RadioApplyRequest(
            frequencyHz: UInt64(max(0, bandSession.frequencyHz.rounded())),
            sampleRate: globalSettings.sampleRate,
            ampEnabled: globalSettings.ampEnabled,
            lnaGain: Int(globalSettings.lnaGain.rounded()),
            vgaGain: Int(globalSettings.vgaGain.rounded()),
            txVGAGain: Int(globalSettings.txVGAGain.rounded()),
            mode: bandSession.mode.rawValue,
            rxFilterHz: bandSession.rxFilterHz
        )
    }

    private func resolvedSelectedSerial(from selectedSerial: String?) -> String? {
        guard let selectedSerial, !selectedSerial.isEmpty else { return nil }
        return selectedSerial
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
