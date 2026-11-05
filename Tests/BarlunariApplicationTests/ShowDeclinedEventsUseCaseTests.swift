import BarlunariApplication
import BarlunariPreviewSupport
import Testing

@Suite struct ShowDeclinedEventsUseCaseTests {
    @Test func 既定は辞退した予定を表示する() {
        #expect(ShowDeclinedEventsDefault.value)
    }

    @Test func 保存がなければ既定の値を返す() {
        #expect(LoadShowDeclinedEventsUseCase(store: InMemoryShowDeclinedEventsStore()).execute())
    }

    @Test(arguments: [true, false]) func 保存した値を返す(value: Bool) {
        #expect(LoadShowDeclinedEventsUseCase(store: InMemoryShowDeclinedEventsStore(value: value)).execute() == value)
    }

    @Test func 保存した値を読み戻せる() {
        let store = InMemoryShowDeclinedEventsStore()
        SaveShowDeclinedEventsUseCase(store: store).execute(false)

        #expect(LoadShowDeclinedEventsUseCase(store: store).execute() == false)
        #expect(store.savedValues == [false])
    }
}
