import CoreGraphics
import Testing

@testable import MenuDatePresentation

@Suite struct MonthPopoverSizingTests {
    @Test func 大きな画面では目標の大きさになる() {
        let size = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 74, width: 2056, height: 1215))
        #expect(size == CGSize(width: 1862, height: 1100))
    }

    @Test func 目標の幅は今のマス目の幅に日の欄と詳細の列と区切り線を足した値になる() {
        let expected: CGFloat = 1120 + 381 + 361
        #expect(MonthPopoverSizing.targetSize.width == expected)
        let grid: CGFloat = 1120 - 24
        #expect(MonthPopoverSizing.gridWidth(popoverWidth: MonthPopoverSizing.targetSize.width, layout: .threeColumn) == grid)
        #expect(MonthPopoverSizing.detailColumnWidth == 360)
    }

    @Test func 二列の下限の幅でもマス目が元の下限の幅を保つ() {
        let expected: CGFloat = 720 + 381
        #expect(MonthPopoverSizing.minimumSize.width == expected)
        let grid: CGFloat = 720 - 24
        #expect(MonthPopoverSizing.gridWidth(popoverWidth: MonthPopoverSizing.minimumSize.width, layout: .twoColumn) == grid)
    }

    @Test func 三列の下限の幅でもマス目が元の下限の幅を保つ() {
        let expected: CGFloat = 720 + 381 + 361
        #expect(MonthPopoverSizing.threeColumnMinimumWidth == expected)
        let grid: CGFloat = 720 - 24
        #expect(MonthPopoverSizing.gridWidth(popoverWidth: MonthPopoverSizing.threeColumnMinimumWidth, layout: .threeColumn) == grid)
    }

    @Test func 余白を引いた幅が3列の下限に届けば3列_届かなければ2列() {
        let margin: CGFloat = 48
        let limit = MonthPopoverSizing.threeColumnMinimumWidth
        func layout(visibleWidth: CGFloat) -> MonthPopoverSizing.PaneLayout {
            MonthPopoverSizing.layout(visibleFrame: CGRect(x: 0, y: 0, width: visibleWidth, height: 1200))
        }
        #expect(layout(visibleWidth: limit + margin) == .threeColumn)
        #expect(layout(visibleWidth: limit + margin - 1) == .twoColumn)
        #expect(layout(visibleWidth: 2056) == .threeColumn)
        #expect(layout(visibleWidth: 1512) == .threeColumn)
        #expect(layout(visibleWidth: 1440) == .twoColumn)
        #expect(layout(visibleWidth: 1280) == .twoColumn)
        #expect(layout(visibleWidth: 400) == .twoColumn)
    }

    @Test func 画面が狭いと縮むのはマス目の幅で_日の欄と詳細の列の幅は変わらない() {
        let wide = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 3000, height: 1200))
        let narrow = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 1700, height: 1200))
        let expected: CGFloat = 1700 - 48
        #expect(narrow.width == expected)
        let removed = wide.width - narrow.width
        #expect(
            MonthPopoverSizing.gridWidth(popoverWidth: narrow.width, layout: .threeColumn)
                == MonthPopoverSizing.gridWidth(popoverWidth: wide.width, layout: .threeColumn) - removed)
        #expect(MonthPopoverSizing.dayPaneWidth == 380)
    }

    @Test func 三列の下限の直前から2列になると詳細の列の分だけ幅が減る() {
        let three = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 1462 + 48, height: 1200))
        #expect(three.width == 1462)
        let two = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 1462 + 47, height: 1200))
        #expect(two.width == 1461)
        // 2 列のマス目は、詳細の列を出さない分だけ広い。
        let expectedGrid: CGFloat = 1461 - 24 - 381
        #expect(MonthPopoverSizing.gridWidth(popoverWidth: two.width, layout: .twoColumn) == expectedGrid)
    }

    @Test func 目標の高さでは1マスに予定の行が8行入る() {
        let row = MonthPopoverSizing.rowHeight(popoverHeight: MonthPopoverSizing.targetSize.height)
        #expect(MonthRowGeometry.laneCapacity(rowHeight: row) == 8)
    }

    @Test func 小さめの画面では高さが余白を引いた大きさに収まる() {
        let size = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
        #expect(size == CGSize(width: 1512 - 48, height: 944 - 48))
        #expect(MonthPopoverSizing.layout(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944)) == .threeColumn)
    }

    @Test func 小さな画面では余白を引いた大きさに収まる() {
        let size = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 25, width: 1280, height: 700))
        #expect(size == CGSize(width: 1280 - 48, height: 700 - 48))
        #expect(MonthPopoverSizing.layout(visibleFrame: CGRect(x: 0, y: 25, width: 1280, height: 700)) == .twoColumn)
    }

    @Test func 非常に小さな画面でも下限を下回らない() {
        let size = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(size == MonthPopoverSizing.minimumSize)
        #expect(MonthPopoverSizing.layout(visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 300)) == .twoColumn)
    }

    @Test func 幅と高さは別々に収める() {
        let size = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 3000, height: 600))
        #expect(size == CGSize(width: 1862, height: 600 - 48))
    }

    @Test func 週の行の高さはマス目の高さを6で割って切り捨てる() {
        let height = MonthPopoverSizing.size(visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944)).height
        let grid = MonthPopoverSizing.gridHeight(popoverHeight: height)
        let row = MonthPopoverSizing.rowHeight(popoverHeight: height)
        #expect(row == (grid / 6).rounded(.down))
        #expect(row * 6 <= grid)
        #expect(grid - row * 6 < 6)
    }

    @Test func 下限の大きさでも予定を描ける高さの行になる() {
        let row = MonthPopoverSizing.rowHeight(popoverHeight: MonthPopoverSizing.minimumSize.height)
        #expect(row >= MonthRowGeometry.dayHeaderHeight)
    }
}
