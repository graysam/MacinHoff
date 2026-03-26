import Foundation

enum FrequencyFormatting {
    static func displayString(for hz: Double) -> String {
        let mhz = hz / 1_000_000
        return String(format: "%.6f MHz", mhz)
    }

    static func compactString(for hz: Double) -> String {
        if hz >= 1_000_000 {
            return String(format: "%.3f MHz", hz / 1_000_000)
        }
        if hz >= 1_000 {
            return String(format: "%.1f kHz", hz / 1_000)
        }
        return String(format: "%.0f Hz", hz)
    }
}
