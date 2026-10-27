import MenuDateApplication
import MenuDateDomain
import MenuDatePreviewSupport
import Testing

/// PreviewSupport のフェイクが、本物のユースケースと組み合わせて期待どおり動くことを確かめる。
@Suite struct SampleDataTests {
    func makeUseCase(visibility: CalendarVisibility = CalendarVisibility()) -> LoadAgendaUseCase {
        LoadAgendaUseCase(
            authorizer: FakeCalendarAccessAuthorizer(),
            calendarRepository: InMemoryCalendarRepository(),
            eventRepository: InMemoryCalendarEventRepository(),
            visibilityRepository: InMemoryCalendarVisibilityRepository(visibility: visibility),
            dateProvider: FixedDateProvider()
        )
    }

    @Test func sampleAgendaCoversMultiDayAllDayAndMeetingEvents() async throws {
        let range = try DayRange(start: SampleData.today, dayCount: 7, calendar: SampleData.calendar)
        let snapshot = try await makeUseCase().execute(range: range)

        #expect(snapshot.days.count == 7)
        #expect(snapshot.days[0].events.map(\.title) == ["朝会", "デザインレビュー", "夕食"])
        #expect(snapshot.days[0].events.contains { $0.meetingURL != nil })
        // 3 日間の終日予定は 10/27 から 10/29 まで
        let offsite = snapshot.days.map { $0.events.contains { $0.title == "開発合宿" } }
        #expect(offsite == [false, false, false, true, true, true, false])
        // 日付をまたぐ夜行バスは 10/29 と 10/30
        #expect(snapshot.days[5].events.contains { $0.title == "夜行バス" })
        #expect(snapshot.days[6].events.contains { $0.title == "夜行バス" })
    }

    @Test func hiddenCalendarDisappearsFromSnapshot() async throws {
        var visibility = CalendarVisibility()
        visibility.hide(SampleData.workCalendar.id)
        let range = try DayRange(start: SampleData.today, dayCount: 1, calendar: SampleData.calendar)
        let snapshot = try await makeUseCase(visibility: visibility).execute(range: range)
        #expect(snapshot.days[0].events.map(\.title) == ["夕食"])
        #expect(snapshot.colorsByDay[SampleData.today] == [SampleData.personalCalendar.color])
    }

    @Test func 二つのアカウントにある同じ祝日の予定は一件だけ出る() async throws {
        let range = try DayRange(start: SampleData.day(2026, 11, 3), dayCount: 1, calendar: SampleData.calendar)
        let snapshot = try await makeUseCase().execute(range: range)
        let holidays = snapshot.days[0].events.filter { $0.title == "文化の日" }
        #expect(holidays.map(\.accountID) == [SampleData.googleAccount.id])
        #expect(SampleData.holidayCalendar.id != SampleData.workAccountHolidayCalendar.id)
        // 祝日の予定は別のカレンダーにあり、UID が同じである。
        let all = SampleData.events.filter { $0.title == "文化の日" }
        #expect(all.count == 2)
        #expect(all[0].iCalendarUID != nil)
        #expect(all[0].sharedKey == all[1].sharedKey)
    }

    @Test func 先のアカウントの祝日を非表示にすると後のアカウントの祝日が残る() async throws {
        var visibility = CalendarVisibility()
        visibility.hide(SampleData.holidayCalendar.id)
        let range = try DayRange(start: SampleData.day(2026, 11, 3), dayCount: 1, calendar: SampleData.calendar)
        let snapshot = try await makeUseCase(visibility: visibility).execute(range: range)
        #expect(snapshot.days[0].events.map(\.accountID) == [SampleData.workAccount.id])
    }

    @Test func 月表示用のサンプルは既存のサンプルを含み追加の予定が重複しない() {
        let extra = SampleData.monthViewEvents.dropFirst(SampleData.events.count)
        #expect(Array(SampleData.monthViewEvents.prefix(SampleData.events.count)) == SampleData.events)
        #expect(extra.count == 16)
        #expect(Set(SampleData.monthViewEvents.compactMap(\.iCalendarUID)).count == SampleData.monthViewEvents.count - 1)
        #expect(extra.allSatisfy { SampleData.calendars.map(\.id).contains($0.calendarIdentity) })
    }

    @Test func 予定の多いサンプルは選べる全日に時刻付きの予定を3から8件持つ() throws {
        let timeline = try WeekTimeline(today: SampleData.today, firstWeekday: SampleData.calendar.firstWeekday)
        let dayCount = timeline.selectableDayRange.days(calendar: SampleData.calendar).count
        let events = SampleData.denseMonthViewEvents
        let perDay = (0..<dayCount).map { index in
            events.filter { $0.eventID.rawValue.hasPrefix("dense-\(index)-") }.count
        }
        #expect(perDay.allSatisfy { (3...8).contains($0) })
        #expect(Set(perDay).count == 6)
        #expect(events.contains { $0.title.count > 30 })
    }

    @Test func 予定の多いサンプルは週ごとに終日と複数日の予定を2から3件持つ() throws {
        let timeline = try WeekTimeline(today: SampleData.today, firstWeekday: SampleData.calendar.firstWeekday)
        let dayCount = timeline.selectableDayRange.days(calendar: SampleData.calendar).count
        let events = SampleData.denseMonthViewEvents
        for week in 0..<(dayCount + 6) / 7 {
            let count = events.filter { $0.eventID.rawValue.hasPrefix("dense-week-\(week)-") }.count
            #expect((2...3).contains(count), "週 \(week) の件数: \(count)")
        }
        let multiDay = events.filter { event in
            if case .allDay(let range) = event.schedule { return range.end > range.start.adding(days: 1, calendar: SampleData.calendar) }
            return false
        }
        #expect(!multiDay.isEmpty)
    }

    @Test func 予定の多いサンプルは同じ入力で同じ予定を返しIDとUIDが重複しない() throws {
        let events = SampleData.denseMonthViewEvents
        #expect(events == SampleData.denseMonthViewEvents)
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(Set(events.compactMap(\.iCalendarUID)).count == events.count)
        let calendarIDs = Set(SampleData.calendars.map(\.id))
        #expect(events.allSatisfy { calendarIDs.contains($0.calendarIdentity) })
    }
}
