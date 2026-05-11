import Foundation

enum Config {
    static var coachAPIURL: URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["COACH_API_URL"],
           let url = URL(string: override)
        {
            return url
        }
        return URL(string: "http://localhost:3000/api/chat")
        #else
        return URL(string: "https://doug-ai.vercel.app/api/chat")
        #endif
    }

    static var coachAPIToken: String? {
        guard let token = Bundle.main.infoDictionary?["COACH_API_TOKEN"] as? String,
              !token.isEmpty,
              token != "YOUR_COACH_API_TOKEN"
        else { return nil }
        return token
    }
}
