import Foundation

enum Config {
    static var anthropicAPIKey: String? {
        Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String
    }

    static var hasAPIKey: Bool {
        guard let key = anthropicAPIKey else { return false }
        return !key.isEmpty && key != "YOUR_ANTHROPIC_API_KEY"
    }
}
