import Foundation
import Testing
@testable import SortedKit

struct StubParser: CaptureParsing {
    var result: Result<ParseResponse, CaptureError>
    func parse(_ request: ParseRequest) async throws -> ParseResponse { try result.get() }
}

@Suite("Capture")
struct CaptureTests {
    let request = ParseRequest(
        text: " Pay rent on the 1st every month, 25,000 ", timeZone: kolkata,
        locale: Locale(identifier: "en_IN"), now: local("2026-11-06T16:30"), listNames: ["Groceries"]
    )

    @Test func requestEncodesSnakeCaseAndLocalTime() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(request)) as! [String: Any]
        #expect(json["timezone"] as? String == "Asia/Kolkata")
        #expect(json["now"] as? String == "2026-11-06T16:30:00")
        #expect(json["list_names"] as? [String] == ["Groceries"])
    }

    @Test func decodesTheSpecSchema() throws {
        let json = """
        {"items": [
          {"kind": "bill", "title": "Pay rent", "due_at": "2026-12-01T09:00:00", "all_day": true,
           "rrule": "FREQ=MONTHLY;BYMONTHDAY=1", "priority": "normal", "amount": 25000, "currency": "INR",
           "list_name": null, "category": null, "needs_clarification": null},
          {"kind": "shopping_item", "title": "Milk", "list_name": "Groceries", "category": "Dairy"}
        ]}
        """
        let response = try JSONDecoder.api.decode(ParseResponse.self, from: Data(json.utf8))
        #expect(response.items.count == 2)
        #expect(response.items[0].kind == .bill)
        #expect(response.items[0].amount == 25_000)
        #expect(response.items[0].allDay)
        #expect(response.items[1].kind == .shoppingItem)
        #expect(response.items[1].priority == .normal)
        #expect(response.items[1].allDay == false)
    }

    @Test func localDateTimeParsing() {
        #expect(LocalDateTime.date(from: "2026-12-01T09:00:00", in: kolkata) == local("2026-12-01T09:00"))
        #expect(LocalDateTime.date(from: "2026-12-01", in: kolkata) == local("2026-12-01T00:00"))
        #expect(LocalDateTime.date(from: "2026-12-01T03:30:00Z", in: kolkata) == local("2026-12-01T09:00"))
        #expect(LocalDateTime.date(from: "next tuesday", in: kolkata) == nil)
    }

    @Test func parsedItemsPassThrough() async {
        let item = ParsedItem(kind: .bill, title: "Pay rent")
        let service = CaptureService(parser: StubParser(result: .success(ParseResponse(items: [item]))))
        let result = await service.capture(request)
        #expect(result == .init(items: [item], outcome: .parsed))
    }

    @Test func nothingParsedFallsBackToAPlainTask() async {
        let service = CaptureService(parser: StubParser(result: .success(ParseResponse(items: []))))
        let result = await service.capture(request)
        #expect(result.outcome == .noItems)
        #expect(result.items == [ParsedItem(kind: .task, title: "Pay rent on the 1st every month, 25,000")])
    }

    @Test func failureKeepsTheText() async {
        for service in [CaptureService(parser: StubParser(result: .failure(.http(status: 500)))), CaptureService(parser: nil)] {
            let result = await service.capture(request)
            #expect(result.outcome == .failed)
            #expect(result.items.first?.title == "Pay rent on the 1st every month, 25,000")
        }
    }

    @Test(arguments: [("Milk", "Dairy"), ("dish soap", "Household"), ("Ice cream", "Frozen"), ("Widgets", "Other")])
    func aisles(name: String, aisle: String) {
        #expect(AisleClassifier.category(for: name) == aisle)
    }
}
