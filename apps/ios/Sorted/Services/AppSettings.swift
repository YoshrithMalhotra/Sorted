import Foundation
import SortedKit

/// Device settings kept in `UserDefaults`. They move to `profiles` once auth lands.
enum AppSettings {
    static let defaultReminderMinutesKey = "defaultReminderMinutes"

    static var defaultReminderTime: TimeOfDay {
        let minutes = UserDefaults.standard.object(forKey: defaultReminderMinutesKey) as? Int
        return minutes.map(TimeOfDay.init(minutesSinceMidnight:)) ?? .defaultReminder
    }
}

/// Values set per build in `Configs/*.xcconfig` and read from Info.plist.
enum AppConfig {
    /// The Sorted API base URL, such as `http://localhost:8000`, or nil when not set.
    static var functionsURL: URL? {
        string("SortedFunctionsURL").flatMap(URL.init(string:))
    }

    static var supabaseAnonKey: String? {
        string("SortedSupabaseAnonKey")
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// The capture service for this build. Without a backend configured, every
    /// capture falls back to a plain task, which keeps the app usable offline.
    static func makeCaptureService() -> CaptureService {
        guard let functionsURL, let supabaseAnonKey else { return CaptureService(parser: nil) }
        return CaptureService(parser: EdgeFunctionParser(functionsURL: functionsURL, apiKey: supabaseAnonKey))
    }
}
