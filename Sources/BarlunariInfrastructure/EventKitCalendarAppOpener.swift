import Foundation
import BarlunariApplication
import BarlunariDomain

/// 予定を標準のカレンダーアプリで開く。URL は `EventKitCalendarStore` が予定から求め、開く操作は `URLOpener` に任せる。
public struct EventKitCalendarAppOpener: CalendarAppOpener {
    private let store: EventKitCalendarStore
    private let urlOpener: any URLOpener

    public init(store: EventKitCalendarStore, urlOpener: any URLOpener) {
        self.store = store
        self.urlOpener = urlOpener
    }

    public func open(_ event: CalendarEvent.Identity) async -> Bool {
        guard let url = await store.calendarAppURL(for: event) else { return false }
        return await MainActor.run { urlOpener.open(url) }
    }
}
