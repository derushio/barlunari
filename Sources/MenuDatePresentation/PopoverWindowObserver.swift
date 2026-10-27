import AppKit
import SwiftUI

/// ポップオーバーのウインドウを取得し、ウインドウが key になったことを ViewModel に伝える。
///
/// どのウインドウのことかの判定は ViewModel が行う。ここでは識別子を渡すだけである。
/// パネルが key になったときが、パネルを開いたときである。
struct PopoverWindowObserver: NSViewRepresentable {
    let viewModel: CalendarPopoverViewModel

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.onWindowChange = { [viewModel] id, isKey in viewModel.popoverWindowDidChange(id, isKey: isKey) }
        view.onWindowBecomeKey = { [viewModel] id in viewModel.windowDidBecomeKey(id) }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {}
}

final class WindowTrackingView: NSView {
    var onWindowChange: (@MainActor (ObjectIdentifier?, Bool) -> Void)?
    var onWindowBecomeKey: (@MainActor (ObjectIdentifier) -> Void)?
    private var observation: NotificationObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window.map { ObjectIdentifier($0) }, window?.isKeyWindow ?? false)
        // 設定ウインドウなど他のウインドウの通知も受け、どれが対象かは ViewModel に判定させる。
        observation = window == nil ? nil : NotificationObservation(
            center: .default, name: NSWindow.didBecomeKeyNotification
        ) { [weak self] source in
            guard let source else { return }
            // queue に .main を指定しているため、メインスレッドで呼ばれる。
            MainActor.assumeIsolated { self?.onWindowBecomeKey?(source) }
        }
    }
}
