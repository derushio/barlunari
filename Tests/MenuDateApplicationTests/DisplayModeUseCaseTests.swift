import MenuDateApplication
import MenuDatePreviewSupport
import Testing

@Suite struct DisplayModeUseCaseTests {
    @Test func 既定のモードは月表示である() {
        #expect(CalendarDisplayMode.default == .month)
    }

    @Test func 保存がなければ既定のモードを返す() {
        let useCase = LoadDisplayModeUseCase(store: InMemoryDisplayModeStore())
        #expect(useCase.execute() == .month)
    }

    @Test func 保存したモードを返す() {
        let useCase = LoadDisplayModeUseCase(store: InMemoryDisplayModeStore(mode: .compact))
        #expect(useCase.execute() == .compact)
    }

    @Test func 保存したモードを読み戻せる() {
        let store = InMemoryDisplayModeStore()
        SaveDisplayModeUseCase(store: store).execute(.compact)

        #expect(LoadDisplayModeUseCase(store: store).execute() == .compact)
        #expect(store.savedModes == [.compact])
    }
}
