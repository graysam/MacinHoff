import SwiftUI

struct SegmentedLevelMeterView: View {
    let title: String
    let baseColor: Color
    let level: Double

    private let segmentCount = 25

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            HStack(alignment: .bottom, spacing: 6) {
                VStack(spacing: 3) {
                    ForEach((0..<segmentCount).reversed(), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: index))
                            .frame(width: 18, height: 8)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    meterMark("+6")
                    Spacer()
                    meterMark("0")
                    Spacer()
                    meterMark("-20")
                }
                .frame(height: CGFloat(segmentCount) * 11)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
    }

    private func color(for index: Int) -> Color {
        let threshold = Double(index + 1) / Double(segmentCount)
        let isLit = level >= threshold
        let dimmed = Color.white.opacity(0.08)

        guard isLit else { return dimmed }
        if threshold > 0.88 { return .red }
        if threshold > 0.72 { return .yellow }
        return baseColor
    }

    private func meterMark(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.65))
    }
}
