import Foundation
import Testing
@testable import SortedKit

let kolkata = TimeZone(identifier: "Asia/Kolkata")!
let newYork = TimeZone(identifier: "America/New_York")!

/// A local date-time in `zone`, written "2026-11-06T09:00".
func local(_ string: String, _ zone: TimeZone = kolkata) -> Date {
    LocalDateTime.date(from: string, in: zone)!
}

func localStrings(_ dates: [Date], _ zone: TimeZone = kolkata) -> [String] {
    dates.map { String(LocalDateTime.string(from: $0, in: zone).prefix(16)) }
}

func expand(
    _ rule: String, from start: String, count: Int = 6, zone: TimeZone = kolkata
) throws -> [String] {
    let rule = try RecurrenceRule(rule)
    let startDate = local(start, zone)
    let end = Calendar(identifier: .gregorian).date(byAdding: .year, value: 12, to: startDate)!
    return localStrings(rule.occurrences(startingAt: startDate, in: zone, from: startDate, to: end, limit: count), zone)
}

@Suite("Parsing")
struct RecurrenceRuleParsingTests {
    @Test("Round-trips to a canonical string", arguments: [
        ("FREQ=MONTHLY;BYMONTHDAY=5", "FREQ=MONTHLY;BYMONTHDAY=5"),
        ("RRULE:FREQ=MONTHLY;BYDAY=-1FR", "FREQ=MONTHLY;BYDAY=-1FR"),
        ("freq=weekly;interval=2;byday=TU", "FREQ=WEEKLY;INTERVAL=2;BYDAY=TU"),
        ("FREQ=DAILY;COUNT=5;INTERVAL=1", "FREQ=DAILY;COUNT=5"),
        ("FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10;UNTIL=20300310", "FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10;UNTIL=20300310"),
        ("FREQ=DAILY;UNTIL=20261231T183000Z", "FREQ=DAILY;UNTIL=20261231T183000Z"),
        ("FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17;WKST=MO", "FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17"),
    ])
    func roundTrip(input: String, canonical: String) throws {
        #expect(try RecurrenceRule(input).rruleString == canonical)
    }

    @Test("Rejects malformed rules", arguments: [
        "", "BYDAY=MO", "FREQ=DAILY;INTERVAL=0", "FREQ=DAILY;COUNT=2;UNTIL=20270101",
        "FREQ=MONTHLY;BYMONTHDAY=0", "FREQ=MONTHLY;BYMONTHDAY=32", "FREQ=WEEKLY;BYDAY=1MO",
        "FREQ=MONTHLY;BYDAY=6MO", "FREQ=DAILY;FREQ=WEEKLY", "FREQ=DAILY;UNTIL=2027",
    ])
    func malformed(input: String) {
        #expect(throws: RecurrenceRuleError.self) { try RecurrenceRule(input) }
    }

    @Test("Rejects rules outside the supported subset", arguments: [
        "FREQ=MINUTELY", "FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1", "FREQ=WEEKLY;WKST=SU",
        "FREQ=YEARLY;BYDAY=MO",
    ])
    func unsupported(input: String) {
        #expect {
            try RecurrenceRule(input)
        } throws: { error in
            if case .unsupported = error as? RecurrenceRuleError { true } else { false }
        }
    }
}

@Suite("Expansion")
struct RecurrenceRuleExpansionTests {
    @Test func monthlyOnThe5th() throws {
        #expect(try expand("FREQ=MONTHLY;BYMONTHDAY=5", from: "2026-11-06T09:00", count: 3)
            == ["2026-12-05T09:00", "2027-01-05T09:00", "2027-02-05T09:00"])
    }

    @Test func endOfMonthUsesMinusOne() throws {
        #expect(try expand("FREQ=MONTHLY;BYMONTHDAY=-1", from: "2027-01-15T09:00", count: 4)
            == ["2027-01-31T09:00", "2027-02-28T09:00", "2027-03-31T09:00", "2027-04-30T09:00"])
    }

    @Test func rawThirtyFirstSkipsShortMonths() throws {
        #expect(try expand("FREQ=MONTHLY;BYMONTHDAY=31", from: "2027-01-01T09:00", count: 3)
            == ["2027-01-31T09:00", "2027-03-31T09:00", "2027-05-31T09:00"])
    }

    @Test func lastFridayOfTheMonth() throws {
        #expect(try expand("FREQ=MONTHLY;BYDAY=-1FR", from: "2026-11-01T18:00", count: 4)
            == ["2026-11-27T18:00", "2026-12-25T18:00", "2027-01-29T18:00", "2027-02-26T18:00"])
    }

    @Test func secondTuesday() throws {
        #expect(try expand("FREQ=MONTHLY;BYDAY=2TU", from: "2026-11-01T10:00", count: 3)
            == ["2026-11-10T10:00", "2026-12-08T10:00", "2027-01-12T10:00"])
    }

    @Test func everyOtherTuesday() throws {
        // Nov 6 2026 is a Friday, so the first Tuesday in its week has passed.
        #expect(try expand("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU", from: "2026-11-06T08:00", count: 3)
            == ["2026-11-17T08:00", "2026-12-01T08:00", "2026-12-15T08:00"])
    }

    @Test func weeklyDefaultsToTheStartWeekday() throws {
        #expect(try expand("FREQ=WEEKLY", from: "2026-11-06T08:00", count: 2)
            == ["2026-11-06T08:00", "2026-11-13T08:00"])
    }

    @Test func weeklyOnSeveralDays() throws {
        #expect(try expand("FREQ=WEEKLY;BYDAY=FR,MO", from: "2026-11-06T07:30", count: 4)
            == ["2026-11-06T07:30", "2026-11-09T07:30", "2026-11-13T07:30", "2026-11-16T07:30"])
    }

    @Test func dailyWithCount() throws {
        #expect(try expand("FREQ=DAILY;COUNT=3", from: "2026-11-06T21:00", count: 10)
            == ["2026-11-06T21:00", "2026-11-07T21:00", "2026-11-08T21:00"])
    }

    @Test func dailyUntilIsInclusiveOfThatDay() throws {
        #expect(try expand("FREQ=DAILY;UNTIL=20261108", from: "2026-11-06T21:00", count: 10)
            == ["2026-11-06T21:00", "2026-11-07T21:00", "2026-11-08T21:00"])
    }

    @Test func yearlyOnStartDate() throws {
        #expect(try expand("FREQ=YEARLY", from: "2027-03-10T09:00", count: 3)
            == ["2027-03-10T09:00", "2028-03-10T09:00", "2029-03-10T09:00"])
    }

    @Test func yearlyOnFebruary29SkipsNonLeapYears() throws {
        #expect(try expand("FREQ=YEARLY", from: "2028-02-29T09:00", count: 2)
            == ["2028-02-29T09:00", "2032-02-29T09:00"])
    }

    @Test func yearlyByMonthAndDay() throws {
        #expect(try expand("FREQ=YEARLY;BYMONTH=1,7;BYMONTHDAY=1", from: "2026-11-06T09:00", count: 3)
            == ["2027-01-01T09:00", "2027-07-01T09:00", "2028-01-01T09:00"])
    }

    @Test func drinkWaterEveryTwoHoursFromNineToSix() throws {
        #expect(try expand("FREQ=HOURLY;INTERVAL=2;BYHOUR=9,11,13,15,17", from: "2026-11-06T09:00", count: 7)
            == ["2026-11-06T09:00", "2026-11-06T11:00", "2026-11-06T13:00", "2026-11-06T15:00",
                "2026-11-06T17:00", "2026-11-07T09:00", "2026-11-07T11:00"])
    }

    @Test func dailyAtSeveralHours() throws {
        #expect(try expand("FREQ=DAILY;BYHOUR=8,20", from: "2026-11-06T08:15", count: 3)
            == ["2026-11-06T08:15", "2026-11-06T20:15", "2026-11-07T08:15"])
    }

    @Test func startIsSkippedWhenItDoesNotMatch() throws {
        // Starts on the 6th; the rule says the 5th.
        let first = try expand("FREQ=MONTHLY;BYMONTHDAY=5", from: "2026-11-06T09:00", count: 1)
        #expect(first == ["2026-12-05T09:00"])
    }

    @Test func impossibleRuleTerminates() throws {
        #expect(try expand("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30", from: "2026-11-06T09:00").isEmpty)
    }

    @Test func keepsLocalTimeAcrossDaylightSaving() throws {
        // US clocks go back on Nov 1 2026 and forward on Mar 14 2027.
        let fall = try expand("FREQ=DAILY", from: "2026-10-30T09:00", count: 4, zone: newYork)
        #expect(fall == ["2026-10-30T09:00", "2026-10-31T09:00", "2026-11-01T09:00", "2026-11-02T09:00"])
        let spring = try expand("FREQ=WEEKLY", from: "2027-03-07T09:00", count: 2, zone: newYork)
        #expect(spring == ["2027-03-07T09:00", "2027-03-14T09:00"])
    }

    @Test func windowJumpMatchesFullExpansion() throws {
        let rule = try RecurrenceRule("FREQ=WEEKLY;INTERVAL=3;BYDAY=MO,TH")
        let start = local("2020-01-02T09:00")
        let lower = local("2026-11-06T00:00")
        let upper = local("2027-02-01T00:00")
        let windowed = rule.occurrences(startingAt: start, in: kolkata, from: lower, to: upper)

        // The same rule with a huge COUNT can't jump, so it walks every period.
        var counted = rule
        counted.count = 100_000
        let walked = counted.occurrences(startingAt: start, in: kolkata, from: lower, to: upper)
        #expect(!windowed.isEmpty)
        #expect(windowed == walked)
    }

    @Test func countIsCountedFromStartNotFromWindow() throws {
        let rule = try RecurrenceRule("FREQ=DAILY;COUNT=5")
        let start = local("2026-11-01T09:00")
        let dates = rule.occurrences(startingAt: start, in: kolkata, from: local("2026-11-04T00:00"), to: local("2026-12-01T00:00"))
        #expect(localStrings(dates) == ["2026-11-04T09:00", "2026-11-05T09:00"])
    }

    @Test func nextOccurrenceIsStrictlyAfter() throws {
        let rule = try RecurrenceRule("FREQ=MONTHLY;BYMONTHDAY=1")
        let start = local("2026-11-01T09:00")
        let next = rule.nextOccurrence(after: start, startingAt: start, in: kolkata)
        #expect(next == local("2026-12-01T09:00"))
    }
}

@Suite("Summary")
struct RecurrenceRuleSummaryTests {
    @Test(arguments: [
        ("FREQ=MONTHLY;BYMONTHDAY=1", "Monthly on the 1st"),
        ("FREQ=MONTHLY;BYMONTHDAY=-1", "Monthly on the last day"),
        ("FREQ=MONTHLY;BYDAY=-1FR", "Monthly on the last Fri"),
        ("FREQ=WEEKLY;INTERVAL=2;BYDAY=TU", "Every 2 weeks on Tue"),
        ("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "Weekly on weekdays"),
        ("FREQ=DAILY;COUNT=3", "Daily, 3 times"),
        ("FREQ=HOURLY;INTERVAL=2;BYHOUR=9,17", "Every 2 hours at 9 AM, 5 PM"),
        ("FREQ=YEARLY;BYMONTH=3;BYMONTHDAY=10", "Yearly on Mar 10"),
        ("FREQ=YEARLY;BYMONTH=1,7;BYMONTHDAY=1", "Yearly on the 1st in Jan, Jul"),
    ])
    func summary(rule: String, expected: String) throws {
        #expect(try RecurrenceRule(rule).summary == expected)
    }
}
