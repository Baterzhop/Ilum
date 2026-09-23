import Foundation

/// The user's selection belongs to one endpoint, not every server the app visits.
@MainActor
public final class ModelPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func model(for endpoint: URL) -> String? {
        defaults.string(forKey: key(endpoint))
    }

    public func setModel(_ name: String?, for endpoint: URL) {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty { defaults.set(value, forKey: key(endpoint)) }
        else { defaults.removeObject(forKey: key(endpoint)) }
    }

    private func key(_ endpoint: URL) -> String { "ilum.preferredModel." + endpoint.absoluteString }
}
