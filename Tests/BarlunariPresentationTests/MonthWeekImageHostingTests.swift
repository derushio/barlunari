import AppKit
import BarlunariDomain
import BarlunariPreviewSupport
import SwiftUI
import Testing

@testable import BarlunariPresentation

/// 画像を貼った行が、画面に描く行（`NSHostingView`）と同じ見た目になること。ウインドウは画面に出さない（オフスクリーン、前面化しない）。
@MainActor
@Suite struct MonthWeekImageHostingTests {
    static let size = CGSize(width: 756, height: 112)

    /// 同期の関数に分けて、ランループを回す。
    private static func runLoop(until date: Date) {
        RunLoop.current.run(until: date)
    }

    /// 行を `NSHostingView` に入れて描いた画素（RGBA）と、倍率。
    static func render(week: Int, viewModel: CalendarPopoverViewModel, scheme: NSAppearance.Name) async -> (pixels: [UInt8], width: Int, height: Int, scale: CGFloat) {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: scheme)
        let hosting = NSHostingView(
            rootView: MonthWeekRowView(viewModel: viewModel, weekIndex: week, rowHeight: size.height)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        hosting.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            Self.runLoop(until: Date().addingTimeInterval(0.03))
            await Task.yield()
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = rep.cgImage!
        return (MonthWeekImageTests.pixels(of: image), image.width, image.height, window.backingScaleFactor)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func 画像を貼った行は画面に描いた行とほぼ同じ画素になる(scheme: NSAppearance.Name) async {
        let viewModel = await MonthWeekImageTests.denseViewModel()
        var worst = 0
        var differing = 0
        for offset in 0..<3 {
            let week = viewModel.displayedMonthFirstWeek + offset
            viewModel.monthImageStore.removeAll()
            let drawn = await Self.render(week: week, viewModel: viewModel, scheme: scheme)
            #expect(viewModel.monthImageStore.weekCount == 0)

            let spec = MonthWeekImageStore.Spec(size: Self.size, colorScheme: scheme == .darkAqua ? .dark : .light, displayScale: drawn.scale)
            MonthIdlePreparation(viewModel: viewModel).prepareWeek(
                week, geometry: MonthRowGeometry(size: Self.size), spec: spec, store: viewModel.monthImageStore
            )
            let pasted = await Self.render(week: week, viewModel: viewModel, scheme: scheme)

            #expect(drawn.pixels.count == pasted.pixels.count)
            let diffs = zip(drawn.pixels, pasted.pixels).map { abs(Int($0) - Int($1)) }
            worst = max(worst, diffs.max() ?? 0)
            differing += diffs.filter { $0 > 6 }.count
        }
        print("画面に描いた行と画像を貼った行(\(scheme.rawValue)): 倍率の差の最大 \(worst)、6 を超える成分 \(differing)")
        #expect(worst <= 20)
    }
}
