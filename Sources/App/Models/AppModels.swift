import Foundation

enum MajorWorkspace: String, CaseIterable, Identifiable {
    case transceiver
    case tinker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transceiver:
            "Transceiver"
        case .tinker:
            "TINKER"
        }
    }
}

enum OperatingMode: String, CaseIterable, Codable, Identifiable {
    case usb = "USB"
    case lsb = "LSB"
    case cw = "CW"
    case am = "AM"
    case nfm = "NFM"

    var id: String { rawValue }
}

enum RegionPreset: String, CaseIterable, Codable, Identifiable {
    case northAmerica
    case region1
    case region3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .northAmerica:
            "North America"
        case .region1:
            "ITU Region 1"
        case .region3:
            "ITU Region 3"
        }
    }
}

struct BandDefinition: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var lowerHz: Double
    var upperHz: Double
    var defaultHz: Double
    var isHidden: Bool
    var isUnlocked: Bool

    init(
        id: UUID = UUID(),
        name: String,
        lowerHz: Double,
        upperHz: Double,
        defaultHz: Double,
        isHidden: Bool = false,
        isUnlocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.lowerHz = lowerHz
        self.upperHz = upperHz
        self.defaultHz = defaultHz
        self.isHidden = isHidden
        self.isUnlocked = isUnlocked
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case lowerHz
        case upperHz
        case defaultHz
        case isHidden
        case isUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        lowerHz = try container.decode(Double.self, forKey: .lowerHz)
        upperHz = try container.decode(Double.self, forKey: .upperHz)
        defaultHz = try container.decode(Double.self, forKey: .defaultHz)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isUnlocked = try container.decodeIfPresent(Bool.self, forKey: .isUnlocked) ?? false
    }
}

struct BandSessionState: Identifiable, Codable, Hashable {
    let id: UUID
    var bandID: UUID
    var frequencyHz: Double
    var txOffsetHz: Double
    var stepHz: Double
    var mode: OperatingMode
    var rxFilterHz: Double
    var txFilterHz: Double
    var squelch: Double
    var agcEnabled: Bool
    var splitEnabled: Bool
    var monitorEnabled: Bool
    var txArmed: Bool
    var visibleSpanHz: Double

    init(
        id: UUID,
        bandID: UUID,
        frequencyHz: Double,
        txOffsetHz: Double,
        stepHz: Double,
        mode: OperatingMode,
        rxFilterHz: Double,
        txFilterHz: Double,
        squelch: Double,
        agcEnabled: Bool,
        splitEnabled: Bool,
        monitorEnabled: Bool,
        txArmed: Bool,
        visibleSpanHz: Double
    ) {
        self.id = id
        self.bandID = bandID
        self.frequencyHz = frequencyHz
        self.txOffsetHz = txOffsetHz
        self.stepHz = stepHz
        self.mode = mode
        self.rxFilterHz = rxFilterHz
        self.txFilterHz = txFilterHz
        self.squelch = squelch
        self.agcEnabled = agcEnabled
        self.splitEnabled = splitEnabled
        self.monitorEnabled = monitorEnabled
        self.txArmed = txArmed
        self.visibleSpanHz = visibleSpanHz
    }

    enum CodingKeys: String, CodingKey {
        case id
        case bandID
        case frequencyHz
        case txOffsetHz
        case stepHz
        case mode
        case rxFilterHz
        case txFilterHz
        case squelch
        case agcEnabled
        case splitEnabled
        case monitorEnabled
        case txArmed
        case visibleSpanHz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        bandID = try container.decode(UUID.self, forKey: .bandID)
        frequencyHz = try container.decode(Double.self, forKey: .frequencyHz)
        txOffsetHz = try container.decode(Double.self, forKey: .txOffsetHz)
        stepHz = try container.decode(Double.self, forKey: .stepHz)
        mode = try container.decode(OperatingMode.self, forKey: .mode)
        rxFilterHz = try container.decode(Double.self, forKey: .rxFilterHz)
        txFilterHz = try container.decode(Double.self, forKey: .txFilterHz)
        squelch = try container.decode(Double.self, forKey: .squelch)
        agcEnabled = try container.decode(Bool.self, forKey: .agcEnabled)
        splitEnabled = try container.decode(Bool.self, forKey: .splitEnabled)
        monitorEnabled = try container.decode(Bool.self, forKey: .monitorEnabled)
        txArmed = try container.decode(Bool.self, forKey: .txArmed)
        visibleSpanHz = try container.decodeIfPresent(Double.self, forKey: .visibleSpanHz) ?? 10_000_000
    }
}

enum WaterfallPalette: String, Codable, CaseIterable, Identifiable {
    case classic
    case ice
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            "Classic SDR"
        case .ice:
            "Ice"
        case .ember:
            "Ember"
        }
    }
}

struct GlobalRadioSettings: Codable, Hashable {
    var sampleRate: Double
    var snapStepHz: Double
    var lnaGain: Double
    var vgaGain: Double
    var txVGAGain: Double
    var ampEnabled: Bool
    var audioInputName: String
    var audioOutputName: String
    var selectedDeviceSerial: String?
    var waterfallPalette: WaterfallPalette
    var waterfallResolutionMultiplier: Int

    init(
        sampleRate: Double,
        snapStepHz: Double,
        lnaGain: Double,
        vgaGain: Double,
        txVGAGain: Double,
        ampEnabled: Bool,
        audioInputName: String,
        audioOutputName: String,
        selectedDeviceSerial: String?,
        waterfallPalette: WaterfallPalette,
        waterfallResolutionMultiplier: Int
    ) {
        self.sampleRate = sampleRate
        self.snapStepHz = snapStepHz
        self.lnaGain = lnaGain
        self.vgaGain = vgaGain
        self.txVGAGain = txVGAGain
        self.ampEnabled = ampEnabled
        self.audioInputName = audioInputName
        self.audioOutputName = audioOutputName
        self.selectedDeviceSerial = selectedDeviceSerial
        self.waterfallPalette = waterfallPalette
        self.waterfallResolutionMultiplier = waterfallResolutionMultiplier
    }

    static let `default` = GlobalRadioSettings(
        sampleRate: 10_000_000,
        snapStepHz: 2_500,
        lnaGain: 16,
        vgaGain: 16,
        txVGAGain: 0,
        ampEnabled: false,
        audioInputName: "System Default",
        audioOutputName: "System Default",
        selectedDeviceSerial: nil,
        waterfallPalette: .classic,
        waterfallResolutionMultiplier: 16
    )

    enum CodingKeys: String, CodingKey {
        case sampleRate
        case snapStepHz
        case lnaGain
        case vgaGain
        case txVGAGain
        case ampEnabled
        case audioInputName
        case audioOutputName
        case selectedDeviceSerial
        case waterfallPalette
        case waterfallResolutionMultiplier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleRate = try container.decodeIfPresent(Double.self, forKey: .sampleRate) ?? Self.default.sampleRate
        snapStepHz = try container.decodeIfPresent(Double.self, forKey: .snapStepHz) ?? Self.default.snapStepHz
        lnaGain = try container.decodeIfPresent(Double.self, forKey: .lnaGain) ?? Self.default.lnaGain
        vgaGain = try container.decodeIfPresent(Double.self, forKey: .vgaGain) ?? Self.default.vgaGain
        txVGAGain = try container.decodeIfPresent(Double.self, forKey: .txVGAGain) ?? Self.default.txVGAGain
        ampEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampEnabled) ?? Self.default.ampEnabled
        audioInputName = try container.decodeIfPresent(String.self, forKey: .audioInputName) ?? Self.default.audioInputName
        audioOutputName = try container.decodeIfPresent(String.self, forKey: .audioOutputName) ?? Self.default.audioOutputName
        selectedDeviceSerial = try container.decodeIfPresent(String.self, forKey: .selectedDeviceSerial)
        waterfallPalette = try container.decodeIfPresent(WaterfallPalette.self, forKey: .waterfallPalette) ?? .classic
        waterfallResolutionMultiplier = min(max(try container.decodeIfPresent(Int.self, forKey: .waterfallResolutionMultiplier) ?? Self.default.waterfallResolutionMultiplier, 8), 64)
    }
}

struct HackRFDevice: Identifiable, Hashable {
    var id: String { serialNumber }
    let serialNumber: String
    let boardName: String
    let displayName: String
    let firmwareVersion: String
    let usbAPIVersion: String
    let sharedUSBDeviceCount: Int
}

enum RadioTransportState: String {
    case idle
    case receiving
    case transmitting
    case fault

    var title: String { rawValue.capitalized }
}

struct RadioDeviceStatus {
    var devices: [HackRFDevice]
    var libraryVersion: String
    var connectedSerialNumber: String?
    var connectionSummary: String
    var lastError: String?
    var transportState: RadioTransportState
    var spectrumBins: [Double]
    var tunedFrequencyHz: Double
    var sampleRate: Double
    var rxRFLevel: Double
    var rxAudioLevel: Double
    var txRFLevel: Double
    var txAudioLevel: Double

    static let placeholder = RadioDeviceStatus(
        devices: [],
        libraryVersion: "Unknown",
        connectedSerialNumber: nil,
        connectionSummary: "No HackRF detected",
        lastError: nil,
        transportState: .idle,
        spectrumBins: Array(repeating: 0, count: 128),
        tunedFrequencyHz: 14_200_000,
        sampleRate: 10_000_000,
        rxRFLevel: 0,
        rxAudioLevel: 0,
        txRFLevel: 0,
        txAudioLevel: 0
    )
}

struct AppPersistenceState: Codable {
    var regionPreset: RegionPreset
    var bandDefinitions: [BandDefinition]
    var bandSessions: [BandSessionState]
    var selectedBandID: UUID?
    var globalSettings: GlobalRadioSettings
}

extension BandDefinition {
    static let unlockedBandName = "Unlocked"

    static func defaults(for preset: RegionPreset) -> [BandDefinition] {
        let baseBands: [BandDefinition]
        switch preset {
        case .northAmerica:
            baseBands = [
                BandDefinition(name: "80m", lowerHz: 3_500_000, upperHz: 4_000_000, defaultHz: 3_900_000),
                BandDefinition(name: "60m", lowerHz: 5_330_500, upperHz: 5_406_500, defaultHz: 5_357_000),
                BandDefinition(name: "40m", lowerHz: 7_000_000, upperHz: 7_300_000, defaultHz: 7_200_000),
                BandDefinition(name: "30m", lowerHz: 10_100_000, upperHz: 10_150_000, defaultHz: 10_125_000),
                BandDefinition(name: "20m", lowerHz: 14_000_000, upperHz: 14_350_000, defaultHz: 14_200_000),
                BandDefinition(name: "17m", lowerHz: 18_068_000, upperHz: 18_168_000, defaultHz: 18_110_000),
                BandDefinition(name: "15m", lowerHz: 21_000_000, upperHz: 21_450_000, defaultHz: 21_200_000),
                BandDefinition(name: "12m", lowerHz: 24_890_000, upperHz: 24_990_000, defaultHz: 24_940_000),
                BandDefinition(name: "10m", lowerHz: 28_000_000, upperHz: 29_700_000, defaultHz: 28_400_000),
                BandDefinition(name: "6m", lowerHz: 50_000_000, upperHz: 54_000_000, defaultHz: 50_125_000),
                BandDefinition(name: "2m", lowerHz: 144_000_000, upperHz: 148_000_000, defaultHz: 146_520_000),
                BandDefinition(name: "1.25m", lowerHz: 222_000_000, upperHz: 225_000_000, defaultHz: 223_500_000),
                BandDefinition(name: "70cm", lowerHz: 420_000_000, upperHz: 450_000_000, defaultHz: 433_920_000),
            ]
        case .region1:
            baseBands = [
                BandDefinition(name: "80m", lowerHz: 3_500_000, upperHz: 3_800_000, defaultHz: 3_650_000),
                BandDefinition(name: "40m", lowerHz: 7_000_000, upperHz: 7_200_000, defaultHz: 7_100_000),
                BandDefinition(name: "30m", lowerHz: 10_100_000, upperHz: 10_150_000, defaultHz: 10_125_000),
                BandDefinition(name: "20m", lowerHz: 14_000_000, upperHz: 14_350_000, defaultHz: 14_200_000),
                BandDefinition(name: "17m", lowerHz: 18_068_000, upperHz: 18_168_000, defaultHz: 18_110_000),
                BandDefinition(name: "15m", lowerHz: 21_000_000, upperHz: 21_450_000, defaultHz: 21_250_000),
                BandDefinition(name: "12m", lowerHz: 24_890_000, upperHz: 24_990_000, defaultHz: 24_930_000),
                BandDefinition(name: "10m", lowerHz: 28_000_000, upperHz: 29_700_000, defaultHz: 28_500_000),
                BandDefinition(name: "6m", lowerHz: 50_000_000, upperHz: 52_000_000, defaultHz: 50_150_000),
                BandDefinition(name: "4m", lowerHz: 70_000_000, upperHz: 70_500_000, defaultHz: 70_200_000),
                BandDefinition(name: "2m", lowerHz: 144_000_000, upperHz: 146_000_000, defaultHz: 145_500_000),
                BandDefinition(name: "70cm", lowerHz: 430_000_000, upperHz: 440_000_000, defaultHz: 433_500_000),
            ]
        case .region3:
            baseBands = [
                BandDefinition(name: "80m", lowerHz: 3_500_000, upperHz: 3_900_000, defaultHz: 3_700_000),
                BandDefinition(name: "40m", lowerHz: 7_000_000, upperHz: 7_300_000, defaultHz: 7_100_000),
                BandDefinition(name: "30m", lowerHz: 10_100_000, upperHz: 10_150_000, defaultHz: 10_120_000),
                BandDefinition(name: "20m", lowerHz: 14_000_000, upperHz: 14_350_000, defaultHz: 14_250_000),
                BandDefinition(name: "17m", lowerHz: 18_068_000, upperHz: 18_168_000, defaultHz: 18_120_000),
                BandDefinition(name: "15m", lowerHz: 21_000_000, upperHz: 21_450_000, defaultHz: 21_300_000),
                BandDefinition(name: "12m", lowerHz: 24_890_000, upperHz: 24_990_000, defaultHz: 24_950_000),
                BandDefinition(name: "10m", lowerHz: 28_000_000, upperHz: 29_700_000, defaultHz: 28_450_000),
                BandDefinition(name: "6m", lowerHz: 50_000_000, upperHz: 54_000_000, defaultHz: 50_110_000),
                BandDefinition(name: "2m", lowerHz: 144_000_000, upperHz: 148_000_000, defaultHz: 146_500_000),
                BandDefinition(name: "70cm", lowerHz: 430_000_000, upperHz: 440_000_000, defaultHz: 433_920_000),
            ]
        }
        return baseBands + [unlocked]
    }

    static var unlocked: BandDefinition {
        BandDefinition(
            name: unlockedBandName,
            lowerHz: 1_000_000,
            upperHz: 6_000_000_000,
            defaultHz: 14_200_000,
            isHidden: false,
            isUnlocked: true
        )
    }
}

extension BandSessionState {
    static func `default`(for band: BandDefinition) -> BandSessionState {
        BandSessionState(
            id: UUID(),
            bandID: band.id,
            frequencyHz: band.defaultHz,
            txOffsetHz: 0,
            stepHz: 2_500,
            mode: band.defaultHz < 30_000_000 ? .usb : .nfm,
            rxFilterHz: 2_700,
            txFilterHz: 2_700,
            squelch: 0,
            agcEnabled: true,
            splitEnabled: false,
            monitorEnabled: false,
            txArmed: false,
            visibleSpanHz: 10_000_000
        )
    }
}

enum SampleRateOption: Double, CaseIterable, Identifiable {
    case mhz0_5 = 500_000
    case mhz1 = 1_000_000
    case mhz1_5 = 1_500_000
    case mhz2 = 2_000_000
    case mhz2_5 = 2_500_000
    case mhz5 = 5_000_000
    case mhz7_5 = 7_500_000
    case mhz10 = 10_000_000
    case mhz12_5 = 12_500_000
    case mhz15 = 15_000_000
    case mhz16 = 16_000_000
    case mhz18 = 18_000_000
    case mhz20 = 20_000_000

    var id: Double { rawValue }

    var title: String {
        let mhz = rawValue / 1_000_000
        if floor(mhz) == mhz {
            return String(format: "%.0f MHz", mhz)
        }
        return String(format: "%.1f MHz", mhz)
    }
}
