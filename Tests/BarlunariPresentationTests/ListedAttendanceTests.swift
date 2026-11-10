import Foundation
import BarlunariDomain
import BarlunariPreviewSupport
import Testing

@testable import BarlunariPresentation

@MainActor @Suite struct ListedAttendanceTests {
    static let schedule = EventSchedule.timed(DateInterval(
        start: SampleData.date(2026, 10, 24, 15, 0), end: SampleData.date(2026, 10, 24, 16, 0)
    ))

    static func event(_ attendance: AttendanceStatus, organizer: Bool = false) -> CalendarEvent {
        let participants = organizer
            ? [try! EventParticipant(name: "自分", emailAddress: nil, isOrganizer: true, isCurrentUser: true)]
            : []
        return CalendarEvent(
            accountID: SampleData.workCalendar.accountID, id: try! EventID("e"), calendarID: SampleData.workCalendar.calendarID,
            title: "予定", schedule: schedule, participants: participants, attendance: attendance
        )
    }

    @Test(arguments: [
        (AttendanceStatus.needsAction, ListedAttendance.needsResponse),
        (.declined, .declined),
        (.accepted, .none),
        (.tentative, .none),
        (.notApplicable, .none),
    ])
    func 出欠を一覧で示す3値に分ける(status: AttendanceStatus, expected: ListedAttendance) {
        #expect(ListedAttendance(Self.event(status)) == expected)
    }

    @Test func 回答できない予定の未回答は示さない() {
        #expect(ListedAttendance(Self.event(.needsAction, organizer: true)) == .none)
    }

    @Test func 予定一覧の行は辞退と未回答を持ち読み上げに含める() async throws {
        let viewModel = await Harness().loadedPopover()
        let rows = viewModel.selectedSection.rows
        #expect(rows.map(\.attendance) == [.none, .none, .declined, .none])
        #expect(rows[2].accessibilityLabel.hasSuffix("辞退"))
        #expect(rows[0].accessibilityLabel == "\(rows[0].timeText)、朝会")

        viewModel.select(SampleData.day(2026, 10, 28))
        await viewModel.waitForLoad()
        let invitation = try #require(viewModel.selectedSection.rows.first { $0.title == "新機能の企画会議" })
        #expect(invitation.attendance == .needsResponse)
        #expect(invitation.accessibilityLabel == "\(invitation.timeText)、新機能の企画会議、会議室 B、未回答")
    }

    @Test func 日の欄のブロックと終日の行は辞退と未回答を持つ() async throws {
        let viewModel = await Harness().loadedPopover()
        let declined = try #require(viewModel.selectedDaySchedule.blocks.first { $0.item.title == "辞退した会議" })
        #expect(declined.item.attendance == .declined)
        #expect(declined.item.accessibilityLabel.hasSuffix("辞退"))
        #expect(viewModel.selectedDaySchedule.blocks.filter { $0.item.attendance != .none }.count == 1)

        viewModel.select(SampleData.day(2026, 10, 28))
        await viewModel.waitForLoad()
        let invitation = try #require(viewModel.selectedDaySchedule.blocks.first { $0.item.title == "新機能の企画会議" })
        #expect(invitation.item.attendance == .needsResponse)
        #expect(invitation.item.accessibilityLabel.hasSuffix("未回答"))
        #expect(viewModel.selectedDaySchedule.allDay.allSatisfy { $0.attendance == .none })
    }

    @Test func 月のマス目の予定は辞退した予定を含まず未回答を持つ() async throws {
        let viewModel = await Harness().loadedPopover()
        let week = viewModel.displayedMonthFirstWeek
        let declinedWeek = viewModel.monthWeekLayout(at: week + 3)
        #expect(declinedWeek.items.first { $0.title == "辞退した会議" } == nil)
        #expect(declinedWeek.items.allSatisfy { $0.attendance != .declined })
        #expect(declinedWeek.items.first { $0.title == "朝会" }?.attendance == ListedAttendance.none)

        let invitationWeek = viewModel.monthWeekLayout(at: week + 4)
        #expect(invitationWeek.items.first { $0.title == "新機能の企画会議" }?.attendance == .needsResponse)
    }

    @Test func 月のマス目の読み上げに未回答と辞退を付ける() {
        func item(_ status: AttendanceStatus) -> MonthWeekLayout.Item {
            let layout = MonthWeekLayoutTests.layout([Self.event(status)])
            return layout.items[0]
        }
        #expect(MonthWeekRowView.accessibilityLabel(of: item(.accepted)).hasSuffix("予定"))
        #expect(MonthWeekRowView.accessibilityLabel(of: item(.declined)).hasSuffix("、辞退"))
        #expect(MonthWeekRowView.accessibilityLabel(of: item(.needsAction)).hasSuffix("、未回答"))
    }
}
