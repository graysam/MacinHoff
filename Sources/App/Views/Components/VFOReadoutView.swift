import SwiftUI

struct VFOReadoutView: View {
    @Binding var frequencyHz: Double
    let stepForward: () -> Void
    let stepBackward: () -> Void

    @State private var draftMHz = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VFO")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if isEditing {
                    TextField("MHz", text: $draftMHz)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .onSubmit(commitDraft)
                } else {
                    Button {
                        draftMHz = String(format: "%.6f", frequencyHz / 1_000_000)
                        isEditing = true
                    } label: {
                        Text(FrequencyFormatting.displayString(for: frequencyHz))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 8) {
                    Button(action: stepForward) {
                        Image(systemName: "chevron.up")
                    }
                    Button(action: stepBackward) {
                        Image(systemName: "chevron.down")
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.9))
        )
        .foregroundStyle(.green)
    }

    private func commitDraft() {
        guard let mhz = Double(draftMHz) else { return }
        frequencyHz = mhz * 1_000_000
        isEditing = false
    }
}
