import SwiftUI

@main
struct MacinHoffApp: App {
    @StateObject private var appModel = AppViewModel()
    @StateObject private var radioModel = RadioControlViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(radioModel)
                .frame(minWidth: 1320, minHeight: 900)
                .onAppear {
                    appModel.onRadioRelevantStateChanged = { [weak radioModel, weak appModel] in
                        guard let radioModel, let appModel else { return }
                        radioModel.apply(globalSettings: appModel.globalSettings, bandSession: appModel.selectedBandSession)
                    }
                    radioModel.startPolling()
                    radioModel.refresh()
                    radioModel.apply(globalSettings: appModel.globalSettings, bandSession: appModel.selectedBandSession)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 960)

        Window("Waterfall", id: "waterfall") {
            WaterfallWindowView()
                .environmentObject(appModel)
                .environmentObject(radioModel)
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}
