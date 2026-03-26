import SwiftUI

struct WaterfallWindowView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @EnvironmentObject private var radioModel: RadioControlViewModel

    var body: some View {
        Group {
            if let band = appModel.selectedBandDefinition,
               let session = appModel.selectedBandSession {
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
                .padding(14)
                .background(Color.black.ignoresSafeArea())
                .overlay(alignment: .topTrailing) {
                    Text("\(band.name) • \(FrequencyFormatting.displayString(for: session.frequencyHz))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(12)
                }
            } else {
                ContentUnavailableView("No Active Tuning", systemImage: "waveform.path.ecg")
            }
        }
        .frame(minWidth: 900, minHeight: 520)
    }
}
