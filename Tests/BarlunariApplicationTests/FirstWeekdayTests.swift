import BarlunariApplication
import BarlunariDomain
import BarlunariPreviewSupport
import Foundation
import Testing

@Suite struct FirstWeekdayUseCaseTests {
    @Test func 保存がなければnilを返す() {
        #expect(LoadFirstWeekdayUseCase(store: InMemoryFirstWeekdayStore()).execute() == nil)
    }

    @Test(arguments: Weekday.allCases) func 保存した曜日を返す(weekday: Weekday) {
        #expect(LoadFirstWeekdayUseCase(store: InMemoryFirstWeekdayStore(value: weekday)).execute() == weekday)
    }

    @Test func 保存した曜日を読み戻せる() {
        let store = InMemoryFirstWeekdayStore()
        SaveFirstWeekdayUseCase(store: store).execute(.monday)

        #expect(LoadFirstWeekdayUseCase(store: store).execute() == .monday)
        #expect(store.savedValues == [.monday])
    }

    @Test func nilを保存すると保存を消してシステムの設定に従う() {
        let store = InMemoryFirstWeekdayStore(value: .friday)
        SaveFirstWeekdayUseCase(store: store).execute(nil)

        #expect(LoadFirstWeekdayUseCase(store: store).execute() == nil)
        #expect(store.savedValues.count == 1)
        #expect(store.savedValues.first! == nil)
    }
}

@Suite struct FirstWeekdayOverridingDateProviderTests {
    private func base(firstWeekday: Int) -> FixedDateProvider {
        var calendar = SampleData.calendar
        calendar.firstWeekday = firstWeekday
        return FixedDateProvider(now: SampleData.now, calendar: calendar)
    }

    @Test func 保存がなければ包んだ暦をそのまま返す() {
        let provider = FirstWeekdayOverridingDateProvider(base: base(firstWeekday: 4), store: InMemoryFirstWeekdayStore())
        #expect(provider.calendar.firstWeekday == 4)
    }

    @Test(arguments: Weekday.allCases) func 保存した曜日で週の開始曜日を置き換える(weekday: Weekday) {
        let provider = FirstWeekdayOverridingDateProvider(
            base: base(firstWeekday: 1), store: InMemoryFirstWeekdayStore(value: weekday)
        )
        #expect(provider.calendar.firstWeekday == weekday.rawValue)
    }

    @Test func 週の開始曜日以外は包んだ暦のままにする() {
        let wrapped = base(firstWeekday: 1)
        let provider = FirstWeekdayOverridingDateProvider(base: wrapped, store: InMemoryFirstWeekdayStore(value: .monday))
        #expect(provider.now == wrapped.now)
        #expect(provider.calendar.timeZone == wrapped.calendar.timeZone)
        #expect(provider.calendar.identifier == wrapped.calendar.identifier)
        #expect(provider.calendar.locale == wrapped.calendar.locale)
    }

    @Test func 保存の変更に追従し消すとシステムの設定に戻る() {
        let store = InMemoryFirstWeekdayStore()
        let provider = FirstWeekdayOverridingDateProvider(base: base(firstWeekday: 1), store: store)

        store.save(.saturday)
        #expect(provider.calendar.firstWeekday == 7)
        store.save(nil)
        #expect(provider.calendar.firstWeekday == 1)
    }

    @Test func 包んだ暦の週の開始曜日の変更にも追従する() {
        let store = InMemoryFirstWeekdayStore()
        let mutable = MutableDateProvider(firstWeekday: 1)
        let provider = FirstWeekdayOverridingDateProvider(base: mutable, store: store)

        mutable.firstWeekday = 2
        #expect(provider.calendar.firstWeekday == 2)
        store.save(.thursday)
        mutable.firstWeekday = 1
        #expect(provider.calendar.firstWeekday == 5)
    }
}

private final class MutableDateProvider: DateProvider, @unchecked Sendable {
    var firstWeekday: Int
    init(firstWeekday: Int) { self.firstWeekday = firstWeekday }
    var now: Date { SampleData.now }
    var calendar: Calendar {
        var calendar = SampleData.calendar
        calendar.firstWeekday = firstWeekday
        return calendar
    }
}
