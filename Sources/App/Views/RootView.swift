import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @EnvironmentObject private var radioModel: RadioControlViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 290)
        } detail: {
            Group {
                switch appModel.workspace {
                case .transceiver:
                    TransceiverWorkspaceView()
                case .tinker:
                    TinkerHomeView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Workspace", selection: $appModel.workspace) {
                        ForEach(MajorWorkspace.allCases) { workspace in
                            Text(workspace.title).tag(workspace)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }
        }
    }
}
