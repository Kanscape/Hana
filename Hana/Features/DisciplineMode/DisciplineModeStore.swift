import Foundation
import Observation

@Observable
final class DisciplineModeStore {
    private(set) var configuration: DisciplineModeConfiguration?
    private(set) var state: DisciplineModeState

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var nowProvider: () -> Date

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.nowProvider = now
        let loadedConfiguration = Self.loadConfiguration(defaults: defaults, decoder: decoder)
        self.configuration = loadedConfiguration
        self.state = DisciplineModeEvaluator.evaluate(
            configuration: loadedConfiguration,
            now: now(),
            calendar: calendar
        )
    }

    var isLocked: Bool {
        state.access == .locked
    }

    func activate(_ configuration: DisciplineModeConfiguration) {
        self.configuration = configuration
        if let data = try? encoder.encode(configuration) {
            defaults.set(data, forKey: HanaSettingsKey.disciplineModeConfiguration)
        }
        refresh()
    }

    func clear() {
        configuration = nil
        defaults.removeObject(forKey: HanaSettingsKey.disciplineModeConfiguration)
        refresh()
    }

    func refresh() {
        state = DisciplineModeEvaluator.evaluate(
            configuration: configuration,
            now: nowProvider(),
            calendar: calendar
        )
    }

    private static func loadConfiguration(defaults: UserDefaults, decoder: JSONDecoder) -> DisciplineModeConfiguration? {
        guard let data = defaults.data(forKey: HanaSettingsKey.disciplineModeConfiguration) else {
            return nil
        }
        return try? decoder.decode(DisciplineModeConfiguration.self, from: data)
    }
}
