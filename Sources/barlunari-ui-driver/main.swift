import AppKit
import Foundation

// Barlunari のポップオーバーを、利用者のカーソルとフォーカスを奪わずに 1 操作ずつ動かす。使い方は .claude/skills/headless-testing/SKILL.md を参照。
// 前面化や activate は呼ばない。利用者のカーソルとフォーカスを奪わない。

let usage = """
使い方:
  barlunari-ui-driver serve <セッションのディレクトリ> [--dense]
  barlunari-ui-driver send <セッションのディレクトリ> "<コマンド>"
コマンド: chain <コマンド> ; <コマンド> / click <x> <y> / hover <x> <y> / scroll <x> <y> <dy> [trackpad|wheel|fling|drag] / key escape|cmd+1|cmd+2 / remote-add <タイトル> / store-change <回数> / wake / hide / show / placement <user|single> <x> <y> [compact] / wait <ms> / screenshot <名前> / quit
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail(usage, code: 2) }
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
/// `serve` の `--dense` は、予定の多いデータ（`SampleData.denseMonthViewEvents`）で起動する。
let isDense = arguments.count == 4 && arguments[3] == "--dense"

switch arguments[1] {
case "send":
    guard arguments.count == 4 else { fail(usage, code: 2) }
    do {
        let line = try Session.send(directory: directory, command: arguments[3])
        print(line)
        exit(line.hasPrefix("error") ? 1 : 0)
    } catch {
        fail("\(error)")
    }
case "serve":
    guard arguments.count == 3 || isDense else { fail(usage, code: 2) }
    NSApplication.shared.setActivationPolicy(.prohibited)
    // トップレベルの await（swift_task_asyncMainDrainQueue）は、AppKit のボタンの追跡ループが抜けるときに
    // ランループが止まると、プロセスごと終了する。そのため、ランループは自前で回し続け、処理は Task で動かす。
    Task { @MainActor in
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 前回の出力が残ると、いまは出していない状態の古い PNG やログを見てしまうため、先に消す。
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where ["png", "fifo", "log"].contains(file.pathExtension) {
                try FileManager.default.removeItem(at: file)
            }
            let requests = try Session.requests(directory: directory)
            let cpuBeforeInit = processCPUMilliseconds()
            let driver = await Driver(directory: directory, dense: isDense)
            // 起動時の初期化（ポップオーバーの組み立て、最初の読み込み、表示が落ち着くまでの待ち）の CPU 時間。
            let cpuInit = processCPUMilliseconds() - cpuBeforeInit
            print("ready \(directory.path) cpuInit=\(String(format: "%.1f", cpuInit)) cpuProcess=\(String(format: "%.1f", processCPUMilliseconds()))")
            fflush(stdout)
            for await request in requests {
                let (line, shouldQuit) = await driver.run(request.command)
                Session.reply(to: request.reply, line)
                if shouldQuit { break }
            }
            unlink(Session.commandPipe(directory))
            exit(0)
        } catch {
            fail("serve に失敗した: \(error)")
        }
    }
    while true { RunLoop.main.run(until: Date(timeIntervalSinceNow: 3600)) }
default:
    fail(usage, code: 2)
}
