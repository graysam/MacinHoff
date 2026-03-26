import SwiftUI

struct BandProfileEditorView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Band Profile Editor")
                        .font(.largeTitle.weight(.bold))
                    Text("Region presets are editable in place. The current implementation preserves per-band state keyed by the current definition IDs.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Table(appModel.bandDefinitions) {
                TableColumn("Band") { band in
                    Text(band.name)
                }
                TableColumn("Lower") { band in
                    Text(FrequencyFormatting.displayString(for: band.lowerHz))
                }
                TableColumn("Upper") { band in
                    Text(FrequencyFormatting.displayString(for: band.upperHz))
                }
                TableColumn("Default") { band in
                    Text(FrequencyFormatting.displayString(for: band.defaultHz))
                }
            }
            .frame(minHeight: 220)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach($appModel.bandDefinitions) { $band in
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Band", text: $band.name)
                            HStack {
                                TextField("Lower Hz", value: $band.lowerHz, format: .number.precision(.fractionLength(0)))
                                TextField("Upper Hz", value: $band.upperHz, format: .number.precision(.fractionLength(0)))
                                TextField("Default Hz", value: $band.defaultHz, format: .number.precision(.fractionLength(0)))
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    }
                }
            }

            HStack {
                Button("Restore Preset") {
                    appModel.updateBandDefinitions(BandDefinition.defaults(for: appModel.regionPreset))
                }
                Button("Apply Edits") {
                    appModel.updateBandDefinitions(appModel.bandDefinitions)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 700)
    }
}
