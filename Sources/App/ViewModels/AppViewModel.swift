import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var workspace: MajorWorkspace = .transceiver
    @Published var regionPreset: RegionPreset
    @Published var bandDefinitions: [BandDefinition]
    @Published var bandSessions: [BandSessionState]
    @Published var selectedBandID: UUID?
    @Published var globalSettings: GlobalRadioSettings
    @Published var showingBandEditor = false
    @Published var showingPoppedOutWaterfall = false

    var onRadioRelevantStateChanged: (() -> Void)?

    private let persistence = PersistenceController()

    init() {
        if let saved = persistence.load() {
            regionPreset = saved.regionPreset
            bandDefinitions = saved.bandDefinitions
            bandSessions = saved.bandSessions
            selectedBandID = saved.selectedBandID ?? saved.bandDefinitions.first?.id
            globalSettings = saved.globalSettings
        } else {
            let defaults = BandDefinition.defaults(for: .northAmerica)
            regionPreset = .northAmerica
            bandDefinitions = defaults
            bandSessions = defaults.map(BandSessionState.default(for:))
            selectedBandID = defaults.first?.id
            globalSettings = .default
        }
        normalizeSessions()
    }

    var selectedBandDefinition: BandDefinition? {
        guard let selectedBandID else { return bandDefinitions.first }
        return bandDefinitions.first(where: { $0.id == selectedBandID }) ?? bandDefinitions.first
    }

    var visibleBandDefinitions: [BandDefinition] {
        bandDefinitions.filter { !$0.isHidden || $0.isUnlocked }
    }

    var selectedBandSession: BandSessionState? {
        guard let band = selectedBandDefinition else { return nil }
        return bandSessions.first(where: { $0.bandID == band.id })
    }

    func bindingForGlobal<T>(_ keyPath: WritableKeyPath<GlobalRadioSettings, T>) -> Binding<T> {
        Binding(
            get: { self.globalSettings[keyPath: keyPath] },
            set: { newValue in
                self.globalSettings[keyPath: keyPath] = newValue
                self.persist()
                self.onRadioRelevantStateChanged?()
            }
        )
    }

    var sampleRateBinding: Binding<Double> {
        Binding(
            get: { self.globalSettings.sampleRate },
            set: { newValue in
                self.globalSettings.sampleRate = newValue
                self.bandSessions = self.bandSessions.map { session in
                    var session = session
                    session.visibleSpanHz = min(max(session.visibleSpanHz, 100), newValue)
                    return session
                }
                self.persist()
                self.onRadioRelevantStateChanged?()
            }
        )
    }

    func bindingForSelectedBand<T>(_ keyPath: WritableKeyPath<BandSessionState, T>, fallback: T) -> Binding<T> {
        Binding(
            get: { self.selectedBandSession?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                self.updateSelectedBand { session in
                    session[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func selectBand(_ bandID: UUID) {
        selectedBandID = bandID
        persist()
        onRadioRelevantStateChanged?()
    }

    func setRegionPreset(_ preset: RegionPreset) {
        regionPreset = preset
        let defaults = BandDefinition.defaults(for: preset)
        let oldSessionsByName = Dictionary(uniqueKeysWithValues: bandSessions.compactMap { session in
            bandDefinitions.first(where: { $0.id == session.bandID }).map { ($0.name, session) }
        })
        let hiddenByName = Dictionary(uniqueKeysWithValues: bandDefinitions.map { ($0.name, $0.isHidden) })
        bandDefinitions = defaults.map { band in
            var band = band
            band.isHidden = hiddenByName[band.name] ?? false
            if band.isUnlocked {
                band.isHidden = false
            }
            return band
        }
        bandSessions = bandDefinitions.map { band in
            if let existing = oldSessionsByName[band.name] {
                var session = existing
                session.bandID = band.id
                session.visibleSpanHz = min(max(session.visibleSpanHz, 100), globalSettings.sampleRate)
                return session
            }
            return .default(for: band)
        }
        selectedBandID = visibleBandDefinitions.first?.id
        persist()
        onRadioRelevantStateChanged?()
    }

    func updateBandDefinitions(_ definitions: [BandDefinition]) {
        bandDefinitions = definitions
        normalizeSessions()
        persist()
        onRadioRelevantStateChanged?()
    }

    func tuneSelectedBand(to frequencyHz: Double) {
        guard let band = selectedBandDefinition else { return }
        let snapped = snappedFrequency(frequencyHz, stepHz: globalSettings.snapStepHz)
        updateSelectedBand { session in
            session.frequencyHz = clampedFrequency(snapped, for: band)
        }
    }

    func stepSelectedBand(by multiplier: Double) {
        guard let session = selectedBandSession else { return }
        tuneSelectedBand(to: session.frequencyHz + (session.stepHz * multiplier))
    }

    func panSelectedBand(by deltaHz: Double) {
        guard let session = selectedBandSession else { return }
        guard let band = selectedBandDefinition else { return }
        updateSelectedBand { selectedSession in
            selectedSession.frequencyHz = clampedFrequency(session.frequencyHz + deltaHz, for: band)
        }
    }

    func zoomSelectedBand(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        let minimumSpan = 100.0
        let maximumSpan = max(globalSettings.sampleRate, minimumSpan)
        updateSelectedBand { session in
            session.visibleSpanHz = min(max(session.visibleSpanHz * factor, minimumSpan), maximumSpan)
        }
    }

    func setBandVisibility(id: UUID, hidden: Bool) {
        guard let index = bandDefinitions.firstIndex(where: { $0.id == id }) else { return }
        if bandDefinitions[index].isUnlocked {
            return
        }
        bandDefinitions[index].isHidden = hidden
        ensureVisibleSelection()
        persist()
    }

    func updateSelectedBand(_ mutate: (inout BandSessionState) -> Void) {
        guard let band = selectedBandDefinition,
              let index = bandSessions.firstIndex(where: { $0.bandID == band.id }) else {
            return
        }

        mutate(&bandSessions[index])
        if !band.isUnlocked {
            bandSessions[index].frequencyHz = min(max(bandSessions[index].frequencyHz, band.lowerHz), band.upperHz)
        }
        bandSessions[index].visibleSpanHz = min(max(bandSessions[index].visibleSpanHz, 100), globalSettings.sampleRate)
        persist()
        onRadioRelevantStateChanged?()
    }

    func resetSelectedBand() {
        guard let band = selectedBandDefinition,
              let index = bandSessions.firstIndex(where: { $0.bandID == band.id }) else {
            return
        }
        bandSessions[index] = .default(for: band)
        persist()
        onRadioRelevantStateChanged?()
    }

    private func normalizeSessions() {
        var sessionMap = Dictionary(uniqueKeysWithValues: bandSessions.map { ($0.bandID, $0) })
        bandSessions = bandDefinitions.map { band in
            var session = sessionMap.removeValue(forKey: band.id) ?? .default(for: band)
            session.visibleSpanHz = min(max(session.visibleSpanHz, 100), globalSettings.sampleRate)
            return session
        }
        ensureVisibleSelection()
    }

    private func ensureVisibleSelection() {
        if selectedBandID == nil || !visibleBandDefinitions.contains(where: { $0.id == selectedBandID }) {
            selectedBandID = visibleBandDefinitions.first?.id
        }
    }

    private func snappedFrequency(_ frequencyHz: Double, stepHz: Double) -> Double {
        guard stepHz > 0 else { return frequencyHz }
        return (frequencyHz / stepHz).rounded() * stepHz
    }

    private func clampedFrequency(_ frequencyHz: Double, for band: BandDefinition) -> Double {
        if band.isUnlocked {
            return frequencyHz
        }
        return min(max(frequencyHz, band.lowerHz), band.upperHz)
    }

    private func persist() {
        persistence.save(
            AppPersistenceState(
                regionPreset: regionPreset,
                bandDefinitions: bandDefinitions,
                bandSessions: bandSessions,
                selectedBandID: selectedBandID,
                globalSettings: globalSettings
            )
        )
    }
}
