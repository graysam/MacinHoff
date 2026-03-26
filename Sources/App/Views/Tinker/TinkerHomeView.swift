import SwiftUI

struct TinkerHomeView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.11),
                    Color(red: 0.12, green: 0.16, blue: 0.13),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Text("TINKER")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                Text("Experimental radio modules live here as separate workspaces. The transceiver shell and HackRF service are already shared so later tools can attach cleanly.")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 18) {
                    TinkerModuleCard(title: "POCSAG RX/TX", summary: "Queued after the core transceiver is stable. This module will reuse the same HackRF and audio infrastructure.")
                    TinkerModuleCard(title: "GPS RX/TX", summary: "Reserved for later signal-generation and decode work. The mode shell is in place so module-specific DSP can land without reshaping the app.")
                }

                Spacer()
            }
            .padding(32)
        }
    }
}

private struct TinkerModuleCard: View {
    let title: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(summary)
                .foregroundStyle(.secondary)
            Spacer()
            Label("Planned", systemImage: "hammer")
                .foregroundStyle(.orange)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
