import SwiftUI

struct HanaServiceReloadAction {
    var action: (URL) -> Void

    func callAsFunction(_ baseURL: URL) {
        action(baseURL)
    }
}

private struct HanaServiceReloadActionKey: EnvironmentKey {
    static let defaultValue = HanaServiceReloadAction { _ in }
}

extension EnvironmentValues {
    var hanaReloadServices: HanaServiceReloadAction {
        get { self[HanaServiceReloadActionKey.self] }
        set { self[HanaServiceReloadActionKey.self] = newValue }
    }
}
