import Foundation
import Security

/// Settings for AI presentation generation: an OpenAI-compatible chat endpoint
/// (OpenRouter by default) plus a separate image endpoint/model for per-slide
/// pictures. Matches the Qt app's `AiConfig` (`generator.h`).
public struct AIConfig: Sendable, Equatable {
    public static let defaultEndpoint = "https://openrouter.ai/api/v1/chat/completions"
    public static let defaultModel = "anthropic/claude-sonnet-4.5"
    public static let defaultKeyEnvironmentVariable = "OPENROUTER_API_KEY"
    public static let defaultImageModel = "google/gemini-2.5-flash-image"

    public var endpoint: String = AIConfig.defaultEndpoint
    public var model: String = AIConfig.defaultModel
    public var keyEnvironmentVariable: String = AIConfig.defaultKeyEnvironmentVariable
    public var imageEndpoint: String = "" // Empty: use `endpoint` above.
    public var imageModel: String = AIConfig.defaultImageModel
    public var outputRoot: String = "" // Empty: ~/Documents/Hype.

    public init() {}
}

/// Persists `AIConfig` in `UserDefaults` — never the API key, which lives only
/// in the environment or the Keychain (see `resolveAPIKey`).
public enum AIConfigStore {
    private static let prefix = "ai."
    public static func load() -> AIConfig {
        let defaults = UserDefaults.standard
        var config = AIConfig()
        if let value = defaults.string(forKey: prefix + "endpoint") { config.endpoint = value }
        if let value = defaults.string(forKey: prefix + "model") { config.model = value }
        if let value = defaults.string(forKey: prefix + "keyEnvironmentVariable") { config.keyEnvironmentVariable = value }
        if let value = defaults.string(forKey: prefix + "imageEndpoint") { config.imageEndpoint = value }
        if let value = defaults.string(forKey: prefix + "imageModel") { config.imageModel = value }
        if let value = defaults.string(forKey: prefix + "outputRoot") { config.outputRoot = value }
        return config
    }
    public static func save(_ config: AIConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.endpoint, forKey: prefix + "endpoint")
        defaults.set(config.model, forKey: prefix + "model")
        defaults.set(config.keyEnvironmentVariable, forKey: prefix + "keyEnvironmentVariable")
        defaults.set(config.imageEndpoint, forKey: prefix + "imageEndpoint")
        defaults.set(config.imageModel, forKey: prefix + "imageModel")
        defaults.set(config.outputRoot, forKey: prefix + "outputRoot")
    }
}

public func defaultOutputRoot() -> String {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Hype").path
}

/// Stores the API key in the login Keychain — used when no environment
/// variable is set (e.g. a GUI app launched from Finder doesn't see shell
/// variables). Matches the Qt app's Keychain use, but calls the Security
/// framework directly instead of shelling out to `security`.
public enum AIKeychain {
    private static let service = "hype-ai-mac"
    private static let account = "default"

    public static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    public static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// The API key and where it came from, or nil if none is configured anywhere.
/// Checks `HYPE_AI_KEY`, then the configured variable, then the Keychain —
/// matching the Qt app's `aiApiKey` (`generator.cpp`).
public func resolveAPIKey(_ config: AIConfig) -> (key: String, source: String)? {
    for name in ["HYPE_AI_KEY", config.keyEnvironmentVariable] where !name.isEmpty {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
            return (value, "environment variable \(name)")
        }
    }
    if let value = AIKeychain.read() {
        return (value, "the macOS Keychain")
    }
    return nil
}
