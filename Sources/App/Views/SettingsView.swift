import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        TabView {
            Form {
                Picker("Waterfall Palette", selection: appModel.bindingForGlobal(\.waterfallPalette)) {
                    ForEach(WaterfallPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }

                Text("The classic SDR palette is black to blue to green to yellow to red to white.")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Display", systemImage: "paintpalette")
            }

            Form {
                ForEach($appModel.bandDefinitions) { $band in
                    if !band.isUnlocked {
                        Toggle("Show \(band.name)", isOn: Binding(
                            get: { !band.isHidden },
                            set: { appModel.setBandVisibility(id: band.id, hidden: !$0) }
                        ))
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Bands", systemImage: "square.stack.3d.up")
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}
