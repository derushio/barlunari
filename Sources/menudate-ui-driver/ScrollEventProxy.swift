import AppKit

/// CGEvent 由来のスクロールの NSEvent は、ウィンドウ番号を保持せず `window` が nil になる。
/// 実イベントの値をそのまま返し、`window` と `locationInWindow` だけを差し替える NSEvent のサブクラスである。
final class ScrollEventProxy: NSEvent {
    nonisolated(unsafe) private var base: NSEvent?
    nonisolated(unsafe) private var targetWindow: NSWindow?
    nonisolated(unsafe) private var number = 0
    nonisolated(unsafe) private var location = NSPoint.zero

    @MainActor
    static func make(base: NSEvent, window: NSWindow, location: NSPoint) -> ScrollEventProxy {
        let proxy = ScrollEventProxy()
        proxy.base = base
        proxy.targetWindow = window
        proxy.number = window.windowNumber
        proxy.location = location
        return proxy
    }

    /// Instruments などで計測中は、AppKit が `sendEvent` の中でイベントトレースのために `cgEvent` を読む。
    /// 元のイベントを返さないと、種類が 0 の例外で serve が落ちる。
    override var cgEvent: CGEvent? { base?.cgEvent }
    override var type: NSEvent.EventType { base?.type ?? .scrollWheel }
    override var window: NSWindow? { targetWindow }
    override var windowNumber: Int { number }
    override var locationInWindow: NSPoint { location }
    override var timestamp: TimeInterval { base?.timestamp ?? 0 }
    override var modifierFlags: NSEvent.ModifierFlags { base?.modifierFlags ?? [] }
    override var phase: NSEvent.Phase { base?.phase ?? [] }
    override var momentumPhase: NSEvent.Phase { base?.momentumPhase ?? [] }
    override var hasPreciseScrollingDeltas: Bool { base?.hasPreciseScrollingDeltas ?? false }
    override var scrollingDeltaX: CGFloat { base?.scrollingDeltaX ?? 0 }
    override var scrollingDeltaY: CGFloat { base?.scrollingDeltaY ?? 0 }
    override var deltaX: CGFloat { base?.deltaX ?? 0 }
    override var deltaY: CGFloat { base?.deltaY ?? 0 }
    override var deltaZ: CGFloat { base?.deltaZ ?? 0 }
    override var isDirectionInvertedFromDevice: Bool { base?.isDirectionInvertedFromDevice ?? false }
}
