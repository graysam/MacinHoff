import SwiftUI

struct BandTabsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(appModel.visibleBandDefinitions) { band in
                        let isSelected = appModel.selectedBandID == band.id
                        Button {
                            appModel.selectBand(band.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(band.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Text(band.isUnlocked ? "No limits" : FrequencyFormatting.compactString(for: band.defaultHz))
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? .black.opacity(0.7) : .secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 13)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 16,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 16,
                                    style: .continuous
                                )
                                .fill(
                                    isSelected
                                    ? (band.isUnlocked ? Color.orange : Color.teal)
                                    : Color(nsColor: .controlBackgroundColor)
                                )
                            )
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(isSelected ? Color.clear : Color.white.opacity(0.08))
                                    .frame(height: 1)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
                                    .mask(alignment: .top) {
                                        Rectangle()
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                        .zIndex(isSelected ? 2 : 1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
        }
        .padding(.bottom, 8)
        .zIndex(10)
    }
}
