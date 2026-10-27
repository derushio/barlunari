import CoreGraphics
import Observation

/// 月表示の大きさを決める、パネルを出すディスプレイの領域（メニューバーの下から Dock の上まで）。
///
/// パネルを開くたびに、出すディスプレイの領域を `update` で渡す。パネルを出す前に渡すので、その大きさでパネルが出る。
@MainActor
@Observable
public final class PopoverScreenArea {
    public private(set) var visibleFrame: CGRect

    public init(visibleFrame: CGRect) {
        self.visibleFrame = visibleFrame
    }

    /// 領域が変わったときだけ値を書く。同じ値を書くと、読んでいる View が評価し直される。
    public func update(_ frame: CGRect) {
        if frame != visibleFrame { visibleFrame = frame }
    }
}
