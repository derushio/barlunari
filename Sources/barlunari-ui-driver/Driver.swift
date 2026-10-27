import CoreGraphics
import BarlunariPresentation
import Darwin
import Foundation

/// プロセスの CPU 時間（user と system の合計）をミリ秒で返す。
func processCPUMilliseconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func milliseconds(_ time: timeval) -> Double { Double(time.tv_sec) * 1000 + Double(time.tv_usec) / 1000 }
    return milliseconds(usage.ru_utime) + milliseconds(usage.ru_stime)
}

/// プロセスが実行した命令数（100 万命令単位）。負荷や CPU の周波数でぶれる ms の代わりに、フレームの重さを比べるために使う。
func processInstructionsMillions() -> Double {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) }
    }
    return result == 0 ? Double(info.ri_instructions) / 1_000_000 : 0
}

/// コマンドを 1 つ実行し、結果の 1 行を返す。
@MainActor
final class Driver {
    private let directory: URL
    private let harness: Harness
    private var step = 0

    init(directory: URL, dense: Bool = false) async {
        self.directory = directory
        harness = await Harness(dense: dense)
    }

    /// `chain <コマンド> ; <コマンド> ; ...` は、最後のコマンドの前の操作では、表示が落ち着くまで待たず、PNG も撮らずに次へ進む。
    /// 操作の直後に次の操作をする、利用者の速い操作を再現するために使う。間を空けたいときは `wait <ms>` を挟む。
    /// 結果の 1 行と PNG は、最後のコマンドのものになる。
    func run(_ command: String) async -> (line: String, shouldQuit: Bool) {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("chain ") {
            let parts = trimmed.dropFirst("chain ".count).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let last = parts.last else { return ("error: 使い方: chain <コマンド> ; <コマンド>", false) }
            for part in parts.dropLast() {
                let result = await run(part, settles: false)
                if result.line.hasPrefix("error") { return result }
            }
            return await run(last, settles: true)
        }
        return await run(command, settles: true)
    }

    private func run(_ command: String, settles: Bool) async -> (line: String, shouldQuit: Bool) {
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.first else { return ("error: コマンドが空である", false) }
        do {
            var label = name
            var frames = ""
            // 計測の範囲は、イベントを送り始めてから、落ち着くまで待つ処理の前まで。PNG を撮る処理は含めない。
            let cpuStart = processCPUMilliseconds()
            switch name {
            case "quit":
                return ("ok quit", true)
            case "click":
                let (x, y) = try point(words)
                try harness.click(x: x, y: y)
            case "hover":
                let (x, y) = try point(words)
                try harness.hover(x: x, y: y)
            case "scroll":
                guard words.count == 4 || words.count == 5, let x = Double(words[1]), let y = Double(words[2]), let dy = Double(words[3]) else {
                    throw DriverError.message("使い方: scroll <x> <y> <dy> [trackpad|wheel|fling|drag]")
                }
                let kindText = words.count == 5 ? words[4] : "trackpad"
                guard let kind = Harness.ScrollKind(rawValue: kindText) else {
                    throw DriverError.message("scroll の種類は trackpad、wheel、fling、drag のどれかである: \(kindText)")
                }
                try await harness.scroll(x: x, y: y, dy: dy, kind: kind)
                if kind == .fling || kind == .drag { frames = Self.frameSummary(harness.lastFrames) }
            case "key":
                guard words.count == 2 else { throw DriverError.message("使い方: key escape|cmd+1|cmd+2") }
                switch words[1] {
                case "escape": try await harness.pressEscape()
                case "cmd+1": try await harness.pressCommand(digit: 1)
                case "cmd+2": try await harness.pressCommand(digit: 2)
                default: throw DriverError.message("使い方: key escape|cmd+1|cmd+2")
                }
                label = "key-\(words[1].replacingOccurrences(of: "+", with: ""))"
            case "remote-add":
                let title = words.dropFirst().joined(separator: " ")
                guard !title.isEmpty else { throw DriverError.message("使い方: remote-add <タイトル>") }
                harness.addRemoteEvent(title: title)
            case "store-change":
                guard words.count == 2, let count = Int(words[1]), count > 0 else { throw DriverError.message("使い方: store-change <回数>") }
                harness.postStoreChanges(count: count)
            case "wake":
                harness.postWake()
            case "hide":
                harness.hidePanel()
            case "show":
                harness.reopenPanel()
            case "placement":
                return (try placement(words, command: command), false)
            case "wait":
                guard words.count == 2, let ms = Int(words[1]), ms >= 0 else { throw DriverError.message("使い方: wait <ms>") }
                await harness.wait(milliseconds: ms)
            case "screenshot":
                guard words.count == 2, words[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                    throw DriverError.message("使い方: screenshot <名前>（英数字と - _ だけ）")
                }
                label = "screenshot-\(words[1])"
            default:
                throw DriverError.message("未知のコマンドである: \(name)")
            }
            let cpu = processCPUMilliseconds() - cpuStart
            if settles { await harness.settle() }
            let cpuSettle = processCPUMilliseconds() - cpuStart
            if !settles { return ("ok", false) }
            step += 1
            let number = String(format: "%03d", step)
            let shot = try harness.screenshot(to: directory.appendingPathComponent("\(number)-\(label).png"))
            let scale = String(format: "%.1f", shot.scale)
            return (
                "step=\(number) cmd=\"\(command)\" png=\(shot.url.path) px=\(shot.pixelWidth)x\(shot.pixelHeight) "
                    + "pt=\(Int(shot.pointWidth))x\(Int(shot.pointHeight)) scale=\(scale) "
                    + "cpu=\(String(format: "%.1f", cpu)) cpuSettle=\(String(format: "%.1f", cpuSettle)) \(harness.panelSummary) \(frames)state: \(harness.stateSummary)",
                false
            )
        } catch {
            return ("error: \(error)", false)
        }
    }

    // MARK: パネルの位置

    /// 仮想のディスプレイの配置。実際の画面にも、メニューバーにも何も出さず、位置の計算（`PopoverPlacement`）だけを実行する。
    /// - `user`: 利用者の 3 枚。内蔵（主）の上に外部が 2 枚並ぶ。外部の `visibleFrame` は `frame` と同じで、メニューバーは 30pt
    /// - `single`: 1 枚。メニューバーの高さ 38pt を `visibleFrame` が除く
    private static let layouts: [String: (displays: [DisplayGeometry], menuBar: CGFloat)] = [
        "user": (
            [
                DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 2056, height: 1329), visibleFrame: CGRect(x: 0, y: 74, width: 2056, height: 1215)),
                DisplayGeometry(frame: CGRect(x: -378, y: 1329, width: 2560, height: 1440), visibleFrame: CGRect(x: -378, y: 1329, width: 2560, height: 1440)),
                DisplayGeometry(frame: CGRect(x: -2938, y: 1329, width: 2560, height: 1440), visibleFrame: CGRect(x: -2938, y: 1329, width: 2560, height: 1440)),
            ],
            30
        ),
        "single": (
            [DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))],
            38
        ),
    ]

    /// `placement <user|single> <クリックの x> <クリックの y> [compact]`。クリックの座標は画面座標（左下原点）。
    /// 出すディスプレイの番号、月表示の大きさを決める領域、パネルのフレームを返す。内容の大きさは、月表示は領域から決まり、`compact` は 300x400。
    private func placement(_ words: [String], command: String) throws -> String {
        let usage = "使い方: placement <user|single> <x> <y> [compact]"
        guard words.count == 4 || words.count == 5, let layout = Self.layouts[words[1]],
              let x = Double(words[2]), let y = Double(words[3]) else { throw DriverError.message(usage) }
        let isCompact = words.count == 5
        if isCompact, words[4] != "compact" { throw DriverError.message(usage) }
        // 外部ディスプレイのボタンのウインドウ。メニューバーの高さに合わせて、クリックの x を中心に置く。
        let click = CGPoint(x: x, y: y)
        let clickDisplay = PopoverPlacement.displayIndex(containing: click, in: layout.displays)
        let button = clickDisplay.map { index -> CGRect in
            let frame = layout.displays[index].frame
            return CGRect(x: x - 20, y: frame.maxY - layout.menuBar, width: 40, height: layout.menuBar)
        }
        guard let plan = PopoverPlacement.plan(click: click, displays: layout.displays, buttonFrame: button, menuBarThickness: layout.menuBar) else {
            throw DriverError.message("ディスプレイがない")
        }
        let content = isCompact ? CGSize(width: 300, height: 400) : PopoverPlacement.monthContentSize(in: plan.visibleArea)
        let frame = PopoverPlacement.frame(contentSize: content, anchor: plan.anchor)
        func rect(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))" }
        return "ok cmd=\"\(command)\" display=\(plan.displayIndex) menuBarBottom=\(Int(plan.anchor.menuBarBottom)) area=\(rect(plan.visibleArea)) "
            + "content=\(Int(content.width))x\(Int(content.height)) panel=\(rect(frame)) top=\(Int(frame.maxY)) inDisplay=\(layout.displays[plan.displayIndex].frame.contains(frame))"
    }

    /// `fling` のフレームの要約。`frames` はフレームの数、`frameCpuMax` と `frameCpuP95` はフレームごとの CPU 時間の最大と
    /// 95 パーセンタイル、`late` は、経過時間が 1 フレームの間隔の 1.5 倍を超えた（次のフレームに間に合わなかった）フレームの数。
    private static func frameSummary(_ frames: [(cpu: Double, wall: Double, instructions: Double)]) -> String {
        guard !frames.isEmpty else { return "" }
        let cpus = frames.map(\.cpu).sorted()
        let p95 = cpus[min(cpus.count - 1, Int(Double(cpus.count) * 0.95))]
        let limit = Harness.flingFrameInterval * 1000 * 1.5
        let late = frames.filter { $0.wall > limit }.count
        return "frames=\(frames.count) frameCpuMax=\(String(format: "%.1f", cpus.last ?? 0)) "
            + "frameCpuP95=\(String(format: "%.1f", p95)) late=\(late) "
            + "frameInsMax=\(String(format: "%.0f", frames.map(\.instructions).max() ?? 0)) "
            + "insList=\(frames.map { String(format: "%.0f", $0.instructions) }.joined(separator: ",")) "
            + "list=\(frames.map { String(format: "%.0f", $0.cpu) }.joined(separator: ",")) "
    }

    private func point(_ words: [String]) throws -> (Double, Double) {
        guard words.count == 3, let x = Double(words[1]), let y = Double(words[2]) else {
            throw DriverError.message("使い方: \(words.first ?? "") <x> <y>")
        }
        return (x, y)
    }
}
