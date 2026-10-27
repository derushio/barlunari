import CoreGraphics
import Testing
@testable import MenuDatePresentation

/// 利用者の 3 枚のディスプレイの配置。内蔵が主で、外部の 2 枚はその上に並ぶ。
/// 外部ディスプレイの `visibleFrame` は `frame` と同じで、上の 30pt はメニューバーで隠れる。
private enum UserLayout {
    static let internalDisplay = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        visibleFrame: CGRect(x: 0, y: 74, width: 2056, height: 1215)
    )
    static let external1 = DisplayGeometry(
        frame: CGRect(x: -378, y: 1329, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -378, y: 1329, width: 2560, height: 1440)
    )
    static let external2 = DisplayGeometry(
        frame: CGRect(x: -2938, y: 1329, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2938, y: 1329, width: 2560, height: 1440)
    )
    static let all = [internalDisplay, external1, external2]
    static let externalMenuBar: CGFloat = 30
    static let month = CGSize(width: 1120, height: 800)

    /// 外部ディスプレイの `index` のメニューバーにある、アイコンのボタンのウインドウのフレーム。
    static func button(on display: DisplayGeometry, x: CGFloat) -> CGRect {
        CGRect(x: x, y: display.frame.maxY - externalMenuBar, width: 40, height: externalMenuBar)
    }
}

@Suite("PopoverPlacement")
struct PopoverPlacementTests {
    private func plan(click: CGPoint, buttonFrame: CGRect? = nil, thickness: CGFloat = 30) -> PopoverPlan? {
        PopoverPlacement.plan(click: click, displays: UserLayout.all, buttonFrame: buttonFrame, menuBarThickness: thickness)
    }

    @Test func 内蔵ディスプレイのアイコンを押すと_メニューバーの下に中心をクリックに合わせて出る() throws {
        let plan = try #require(plan(click: CGPoint(x: 1000, y: 1310)))
        #expect(plan.displayIndex == 0)
        // visibleFrame の上端 1289 がメニューバーの下端。上端はそこから 4pt 下がる。
        #expect(plan.anchor.menuBarBottom == 1289)
        let frame = PopoverPlacement.frame(contentSize: UserLayout.month, anchor: plan.anchor)
        #expect(frame == CGRect(x: 440, y: 1285 - 800, width: 1120, height: 800))
        #expect(plan.visibleArea == CGRect(x: 0, y: 74, width: 2056, height: 1215))
    }

    @Test func 左の外部ディスプレイのアイコンを押すと_そのディスプレイのメニューバーの下に出る() throws {
        let display = UserLayout.external1
        let button = UserLayout.button(on: display, x: 980)
        let plan = try #require(plan(click: CGPoint(x: 1000, y: 2760), buttonFrame: button))
        #expect(plan.displayIndex == 1)
        // visibleFrame が frame と同じなので、ボタンの下端 2739（上端 2769 - 30）を使う。
        #expect(plan.anchor.menuBarBottom == 2739)
        let frame = PopoverPlacement.frame(contentSize: UserLayout.month, anchor: plan.anchor)
        #expect(frame == CGRect(x: 440, y: 2735 - 800, width: 1120, height: 800))
        #expect(plan.visibleArea == CGRect(x: -378, y: 1329, width: 2560, height: 1410))
    }

    @Test func 一番左の外部ディスプレイのアイコンを押すと_そのディスプレイに出る() throws {
        let display = UserLayout.external2
        let plan = try #require(plan(click: CGPoint(x: -1500, y: 2760)))
        #expect(plan.displayIndex == 2)
        let frame = PopoverPlacement.frame(contentSize: UserLayout.month, anchor: plan.anchor)
        #expect(frame.minX == -2060)
        #expect(frame.maxY == display.frame.maxY - 30 - PopoverPlacement.gap)
        #expect(display.frame.contains(frame))
    }

    @Test func ボタンのウインドウが別のディスプレイにあるときは_メニューバーの高さで下端を決める() throws {
        // ボタンのフレームは内蔵ディスプレイのもの。クリックは外部ディスプレイにある。
        let button = CGRect(x: 1900, y: 1289, width: 40, height: 40)
        let plan = try #require(plan(click: CGPoint(x: 1000, y: 2760), buttonFrame: button))
        #expect(plan.displayIndex == 1)
        #expect(plan.anchor.menuBarBottom == CGFloat(2739))
    }

    @Test func 画面の右端のアイコンを押すと_右の余白の内側に収まる() throws {
        let display = UserLayout.external1
        let plan = try #require(plan(click: CGPoint(x: display.frame.maxX - 20, y: 2760)))
        let frame = PopoverPlacement.frame(contentSize: UserLayout.month, anchor: plan.anchor)
        #expect(frame.maxX == display.frame.maxX - PopoverPlacement.edgeMargin)
        #expect(frame.width == 1120)
    }

    @Test func 画面の左端のアイコンを押すと_左の余白の内側に収まる() throws {
        let display = UserLayout.external2
        let plan = try #require(plan(click: CGPoint(x: display.frame.minX + 5, y: 2760)))
        let frame = PopoverPlacement.frame(contentSize: UserLayout.month, anchor: plan.anchor)
        #expect(frame.minX == display.frame.minX + PopoverPlacement.edgeMargin)
    }

    @Test func パネルが可視領域より大きいときは_余白の内側に収まる大きさに縮む() throws {
        let plan = try #require(plan(click: CGPoint(x: 1000, y: 1310)))
        let frame = PopoverPlacement.frame(contentSize: CGSize(width: 3000, height: 3000), anchor: plan.anchor)
        let visible = UserLayout.internalDisplay.visibleFrame
        #expect(frame.width == visible.width - 2 * PopoverPlacement.edgeMargin)
        #expect(frame.minX == visible.minX + PopoverPlacement.edgeMargin)
        #expect(frame.maxY == 1289 - PopoverPlacement.gap)
        #expect(frame.minY == visible.minY + PopoverPlacement.edgeMargin)
    }

    @Test(arguments: [200.0, 400.0, 800.0, 1100.0])
    func 内容の高さが変わっても_上端は動かない(height: Double) throws {
        let plan = try #require(plan(click: CGPoint(x: 1000, y: 2760)))
        let frame = PopoverPlacement.frame(contentSize: CGSize(width: 300, height: height), anchor: plan.anchor)
        #expect(frame.maxY == 2739 - PopoverPlacement.gap)
        #expect(frame.height == CGFloat(height))
    }

    @Test func クリックがどのディスプレイにもないときは_ボタンのあるディスプレイの中心に合わせる() throws {
        let button = UserLayout.button(on: UserLayout.external2, x: -1000)
        let plan = try #require(plan(click: CGPoint(x: 9000, y: 9000), buttonFrame: button))
        #expect(plan.displayIndex == 2)
        #expect(plan.anchor.clickX == button.midX)
    }

    @Test func クリックもボタンもないときは_先頭のディスプレイに出す() throws {
        let plan = try #require(plan(click: CGPoint(x: 9000, y: 9000)))
        #expect(plan.displayIndex == 0)
    }

    @Test func ディスプレイがなければ計画を立てない() {
        #expect(PopoverPlacement.plan(click: .zero, displays: [], buttonFrame: nil, menuBarThickness: 24) == nil)
    }

    @Test func ディスプレイの境目の点は_上側の外部ディスプレイに属する() {
        // 内蔵の上端 1329 は、内蔵の範囲の外（半開区間）で、外部ディスプレイの下端。
        #expect(PopoverPlacement.displayIndex(containing: CGPoint(x: 0, y: 1329), in: UserLayout.all) == 1)
        #expect(PopoverPlacement.displayIndex(containing: CGPoint(x: 0, y: 1328.5), in: UserLayout.all) == 0)
    }

    @Test func 月表示の領域は_メニューバーの下からDockの上まで() {
        let internalArea = PopoverPlacement.visibleArea(of: UserLayout.internalDisplay, menuBarBottom: 1289)
        #expect(internalArea.height == 1215)
        // 領域から求めた月表示の大きさは、どのディスプレイでも目標の大きさになる。
        for area in [internalArea, CGRect(x: -378, y: 1329, width: 2560, height: 1410)] {
            #expect(MonthPopoverSizing.size(visibleFrame: area) == MonthPopoverSizing.targetSize)
        }
    }

    @Test func 小さなディスプレイでは_月表示は縮み_下限を下回らない() {
        let small = DisplayGeometry(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 1280, height: 775)
        )
        let plan = PopoverPlacement.plan(click: CGPoint(x: 640, y: 790), displays: [small], buttonFrame: nil, menuBarThickness: 25)
        let area = plan?.visibleArea ?? .zero
        let size = MonthPopoverSizing.size(visibleFrame: area)
        #expect(size == CGSize(width: 1280 - 48, height: 727))
        let frame = PopoverPlacement.frame(contentSize: size, anchor: plan!.anchor)
        #expect(small.visibleFrame.contains(frame))
    }
}
