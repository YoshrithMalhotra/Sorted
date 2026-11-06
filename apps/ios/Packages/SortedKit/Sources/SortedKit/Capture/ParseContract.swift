import Foundation

// The `POST /parse` contract from the MVP spec, written by hand until
// packages/contracts exists and the Swift models are generated from it.

public enum CaptureKind: String, Codable, Sendable, CaseIterable {
    case reminder
    case task
    case bill
    case shoppingItem = "shopping_item"

    public var title: String {
        switch self {
        case .reminder: "Reminder"
        case .task: "Task"
        case .bill: "Bill"
        case .shoppingItem: "Shopping"
        }
    }
}

public enum Priority: String, Codable, Sendable, CaseIterable, Comparable {
    case high, normal, low

    private var rank: Int {
        switch self {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }

    /// High sorts first.
    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rank < rhs.rank }
}

public struct ParseRequest: Codable, Hashable, Sendable {
    public var text: String
    /// IANA time zone, for example "Asia/Kolkata".
    public var timezone: String
    public var locale: String
    /// The current local time, as "2026-11-06T16:30:00".
    public var now: String
    public var listNames: [String]

    public init(text: String, timeZone: TimeZone, locale: Locale, now: Date, listNames: [String]) {
        self.text = text
        self.timezone = timeZone.identifier
        self.locale = locale.identifier
        self.now = LocalDateTime.string(from: now, in: timeZone)
        self.listNames = listNames
    }
}

public struct ParsedItem: Codable, Hashable, Sendable {
    public var kind: CaptureKind
    public var title: String
    /// Local date-time of the first occurrence, without an offset.
    public var dueAt: String?
    /// True when no time was given; the app uses the default reminder time.
    public var allDay: Bool
    public var rrule: String?
    public var priority: Priority
    public var amount: Decimal?
    public var currency: String?
    public var listName: String?
    public var category: String?
    public var needsClarification: String?

    public init(
        kind: CaptureKind, title: String, dueAt: String? = nil, allDay: Bool = false,
        rrule: String? = nil, priority: Priority = .normal, amount: Decimal? = nil,
        currency: String? = nil, listName: String? = nil, category: String? = nil,
        needsClarification: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.dueAt = dueAt
        self.allDay = allDay
        self.rrule = rrule
        self.priority = priority
        self.amount = amount
        self.currency = currency
        self.listName = listName
        self.category = category
        self.needsClarification = needsClarification
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(CaptureKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        dueAt = try container.decodeIfPresent(String.self, forKey: .dueAt)
        allDay = try container.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        rrule = try container.decodeIfPresent(String.self, forKey: .rrule)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        listName = try container.decodeIfPresent(String.self, forKey: .listName)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        needsClarification = try container.decodeIfPresent(String.self, forKey: .needsClarification)
    }
}

public struct ParseResponse: Codable, Hashable, Sendable {
    public var items: [ParsedItem]

    public init(items: [ParsedItem]) {
        self.items = items
    }
}

extension JSONDecoder {
    /// Decodes the API's snake_case JSON.
    public static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

extension JSONEncoder {
    /// Encodes snake_case JSON for the API.
    public static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
