import Foundation

struct PersistenceController {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> AppPersistenceState? {
        guard let data = try? Data(contentsOf: stateURL) else {
            return nil
        }
        return try? decoder.decode(AppPersistenceState.self, from: data)
    }

    func save(_ state: AppPersistenceState) {
        do {
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("Failed to persist app state: %@", error.localizedDescription)
        }
    }

    private var stateURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MacinHoff", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }
}
