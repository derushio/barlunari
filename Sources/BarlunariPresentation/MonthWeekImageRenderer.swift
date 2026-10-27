import CoreGraphics
import SwiftUI

/// 行の画像を描く。`ImageRenderer` に、行の `Canvas` と同じ `MonthWeekPainter` を渡して描くので、画像にする前と後で描く内容は同じである。
///
/// 画像は、`Spec` の倍率（ディスプレイの倍率）の画素で描き、ライトとダークは環境の値で決める。
@MainActor
enum MonthWeekImageRenderer {
    /// 日の数字と今日の印の画像と、行の座標での位置。日の数字の領域だけを切り出す。
    static func cellsImage(days: [MonthDayState], spec: MonthWeekImageStore.Spec) -> (image: CGImage?, rect: CGRect) {
        let rect = CGRect(x: 0, y: 0, width: spec.size.width, height: min(spec.size.height, MonthRowGeometry.dayHeaderHeight))
        let size = spec.size
        let image = render(rect: rect, spec: spec) { context in
            MonthWeekPainter.drawCells(days, in: &context, geometry: MonthRowGeometry(size: size))
        }
        return (image, rect)
    }

    /// 予定のバー、時刻付きの予定、「他 N 件」の画像と、行の座標での位置。予定のある行の範囲だけを切り出す。予定がなければ `nil`。
    static func eventsImage(visible: MonthWeekLayout.Visible, spec: MonthWeekImageStore.Spec) -> (image: CGImage?, rect: CGRect) {
        let geometry = MonthRowGeometry(size: spec.size)
        guard let rect = MonthWeekPainter.eventsExtent(visible, geometry: geometry) else { return (nil, .zero) }
        let image = render(rect: rect, spec: spec) { context in
            MonthWeekPainter.drawEvents(visible, in: &context, geometry: geometry)
        }
        return (image, rect)
    }

    /// `rect`（行の座標）の範囲を、`draw` で描いた画像にする。
    private static func render(
        rect: CGRect, spec: MonthWeekImageStore.Spec, draw: @escaping @Sendable (inout GraphicsContext) -> Void
    ) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let origin = rect.origin
        let content = Canvas { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
            draw(&context)
        }
        .frame(width: rect.width, height: rect.height)
        .environment(\.colorScheme, spec.colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = spec.scale
        renderer.isOpaque = false
        return renderer.cgImage
    }
}
