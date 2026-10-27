---
name: headless-testing
description: Barlunari のテストを書く・実行するとき、フェイクやスタブを用意するとき、スナップショットの PNG で見た目を確かめるとき、アプリの起動確認をするときに使います。カーソルやフォーカスを奪わないヘッドレスのテスト方針を定めます。
---

# headless-testing

このプロジェクトのテストと動作確認は、利用者のカーソルとフォーカスを奪わないヘッドレスな方法だけで行います。

## 禁止事項

- 画面に表示するウィンドウを開くテストを書かない。スナップショットのオフスクリーンの `NSWindow` と、操作ツールの完全に透明で背面の `NSWindow` は、利用者の目にも操作にも触れないので例外とする
- AppleScript、`cliclick`、`osascript` などでカーソルやフォーカスを操作しない
- `open` を `-g -j` なしで使って、アプリを前面に出さない。起動確認は `open -g -j <Barlunari.app のパス>` で行う
- 画面を操作する UI テストを書かない

## Swift Testing の書き方

- `import Testing` を使い、`@Test` と `#expect` で書く。XCTest は使わない
- テスト関数名は振る舞いを表す。例は `func 終日予定は重なるすべての日に入る()` です
- 関連するテストは `@Suite` でまとめる
- 入力だけが違う場合は `@Test(arguments:)` でパラメーター化する
- 非同期のテストは `async throws` で書く。時間を待つ `sleep` は使わず、フェイクで制御する
- 現在時刻は `DateProvider` のフェイクで固定し、`Calendar` とタイムゾーンもテスト側で指定する

## レイヤーごとのテスト

| レイヤー | 何でテストするか |
| --- | --- |
| Domain | 依存なしの単体テスト。不正な値で `DomainError` が投げられること、`AgendaBuilder` の並び順と除外条件を確かめる |
| Application | `BarlunariPreviewSupport` のフェイクのリポジトリとポートでユースケースをテストする |
| Infrastructure | `EventKitMapper` を `EventKitEventValue` などの値で確かめる。`EKEventStore` に触れるテストは書かない。許可のダイアログが出て、フォーカスを奪うためである。UserDefaults の代わりにテスト専用の suite を使い、実物に触れない形にする |
| Presentation | 位置の計算（`PopoverPlacement`）と閉じ方の判断（`PopoverEscapeAction`、`PopoverToggleGate`）は純粋な値のテストで確かめる。`MenuBarPanel` は画面に出さず（`orderFront`、`makeKey` を呼ばず）、内容の大きさを変えて、フレームの書き直しと上端が動かないことを確かめる。`NSStatusItem` は作らない。PreviewSupport のフェイクで ViewModel を組み立てて `Harness` でテストする。URL を開く処理は `FakeURLOpener` に差し替える。日付の変更などの通知は、専用の `NotificationCenter` で流す。複数のアカウントは `SampleData.accounts` の 2 アカウントで確かめ、許可の状態は `Harness` の `status` と `statusAfterRequest`、カレンダーがない状態は `accounts` と `calendars` に空を渡して再現する。ウインドウは開かず、ViewModel の状態を検証する |
| 見た目 | `barlunari-snapshots` で PNG にして目で確かめる |

## フェイクの置き場所

フェイク実装とサンプルデータは `BarlunariPreviewSupport` に置きます。テストターゲットごとに同じフェイクを重複して書かず、ここを共有します。フェイクは Domain と Application のプロトコルだけに依存します。`FakeCalendarAccessAuthorizer`、`FakeSystemSettingsOpener`、`FakeLaunchAtLoginService`、`FakeURLOpener`、`FixedDateProvider`、`InMemoryCalendarRepository`、`InMemoryCalendarEventRepository`、`InMemoryCalendarVisibilityRepository`、`InMemoryDisplayModeStore`、`SampleData` があります。テスト固有の挙動が要るフェイクは、各テストターゲットの `Fakes.swift` や `TestSupport.swift` に置いてかまいません。

## EventKit の値によるテスト

- EventKit の型は `Sendable` ではなく、実物の `EKEventStore` は許可のダイアログを出すため、テストでは使わない。`EventKitCalendarStore` はテストしない
- `EventKitMapper` は、`EventKitValues.swift` の値（`EventKitSourceValue`、`EventKitCalendarValue`、`EventKitEventValue`）を作って確かめる。`@testable import BarlunariInfrastructure` で内部の型を使う。暦は `FixedDateProvider` で固定する
- 分岐ごとにテストを書く。終日予定の終了日、複数日の終日予定、終了が開始より前の予定、出欠の対応表、会議の URL を探す順、会議サービスでない URL を飛ばす場合、メモの URL の末尾の句読点がある
- 許可の状態は `FakeCalendarAccessAuthorizer` で再現する。`status` に `.notDetermined`、`.denied`、`.fullAccess` を渡し、`requestError` で許可を求める操作の失敗を再現する。システム設定を開く操作は `FakeSystemSettingsOpener` が記録する
- 予定の詳細は、ViewModel のテストで、詳細の開閉、一覧に戻る条件、読み直しでの扱い、URL を開く処理を確かめる。読み直しは `ScriptedEventRepository` の `gate()` と `resume(at:events:)` で、返す予定を差し替えて再現する。URL を開く処理は `FakeURLOpener` が記録する。`SampleData` の「デザインレビュー」は、詳細の全項目を持つ
- 重複の除去は `AgendaBuilder` のテストで、`iCalendarUID` を持つ予定と持たない予定を使って確かめる。`SampleData` の祝日の予定は、2 つのアカウントで UID が同じになる

## スナップショットで見た目を確かめる手順

1. `swift run barlunari-snapshots .playwright/snapshots` を実行する。画面に出さないオフスクリーンの `NSWindow` に `NSHostingView` を入れ、`cacheDisplay` で PNG にする。`NSApplication.shared.setActivationPolicy(.prohibited)` を呼ぶので、前面にもキーにもならず、利用者のフォーカスを奪わない。`makeKeyAndOrderFront` と `activate` は呼ばない
2. 複数のアカウントの見た目は、アカウントごとのセクションのカレンダータブの PNG で確かめる。許可が未決定、拒否、カレンダーなしの案内は、ポップオーバーと設定のカレンダータブの PNG で確かめる。予定の詳細は `popover-detail-light`、`popover-detail-dark`、`popover-detail-minimal` で確かめる。表示するカレンダーの一覧は `month-calendars-light`、`month-calendars-dark`、`popover-calendars-light`、`popover-calendars-dark` で確かめる。狭い画面の 2 列は `month-two-column-light`、`month-two-column-detail-light`、`month-two-column-calendars-light` で確かめる。3 列の月表示は、詳細の列の空の状態を `month-light`、詳細を `month-detail-*`、一覧を `month-calendars-*` で確かめ、ほかに `month-light`、`month-dark`、`month-detail-light`、`month-detail-dark`、`month-day-today`（今日の線）、`month-day-events`、`month-day-events-detail`（日の欄の詳細）、`month-day-overlap-light`、`month-day-overlap-dark`（重なる予定と終日の予定）、`month-day-events-empty`、`month-day-dense`、`month-next-month`、`month-not-determined`、`month-denied`、`month-error`、`month-loading` で確かめる。詳細の内容がスクロールで切れる長さのときは、`EventDetailView.maxHeight` を一時的に大きくして全項目を描き、確かめた後に戻す
3. 出力された PNG を Read ツールで開き、意図した見た目かを自分の目で確かめる。寸法の数値だけで完了にしない
4. 崩れや欠けがあれば View を直し、1 から繰り返す
5. 新しい画面や状態を足したときは、`barlunari-snapshots` にも追加する。ViewModel は `Fixture` が PreviewSupport のフェイクで組み立てる

## AIUI テスト（barlunari-ui-driver）

ポップオーバーを AI が 1 操作ずつ動かし、操作のたびに PNG を見て判断する。`barlunari-ui-driver` が、本物の `CalendarPopoverView` と `CalendarPopoverViewModel` を `BarlunariPreviewSupport` のフェイクと固定の現在日時で組み立て、アプリと同じ `MenuBarPanel`（同じ `NSHostingView` の設定と同じフレームの決め方）に載せ、ディスプレイの範囲内に完全に透明にして置く。合成した `NSEvent` をアプリのイベントキューへ直接渡すので、利用者のカーソルとフォーカスは奪わない。`CGEvent.post`、AppleScript、`cliclick` は使わない。

### 手順

1. `swift build --product barlunari-ui-driver` でビルドする
2. Bash ツールの `run_in_background: true` で、`serve` を 1 回だけ起動する。コマンドは `<worktree の絶対パス>/.build/debug/barlunari-ui-driver serve <worktree の絶対パス>/.playwright/ui` のように、絶対パスで書く。起動時に、そのディレクトリの古い PNG、ログ、パイプを削除する。`rm` は使わない
   予定の多いデータで測るときは、末尾に `--dense` を付ける（`serve <ディレクトリ> --dense`）。選べる全日に時刻付きの予定が 3〜8 件、週ごとに終日や複数日の予定が 2〜3 件、長いタイトルもある。`SampleData.denseMonthViewEvents` を使う。付けなければ `SampleData.monthViewEvents` である
3. 1 回の Bash 呼び出しで 1 操作だけ、前面で `send` を実行する。`send` は `serve` の準備ができるまで待ち、操作の結果が出たら 1 行を返す

   ```sh
   .build/debug/barlunari-ui-driver send .playwright/ui "click 100 345"
   ```

4. 結果の 1 行にある PNG を Read ツールで開き、意図した状態かを自分の目で判断する。1 行には、手順の番号、コマンド、PNG のパス、画素の寸法（`px`）、ポイントの寸法（`pt`）、倍率（`scale`）、操作の CPU 時間（`cpu`、`cpuSettle`）、ViewModel の状態（表示モード、選択日、表示月、状態、開いている詳細のタイトル、一覧の日数、選択日の件数と内訳）が入る。パネルのフレームは `panel=x,y,幅,高さ top=上端` で、表示モードの切り替えとコンパクト表示の詳細の開閉で、高さが内容に合わせて変わり、`top` が動かないことを確かめる。`カレンダー一覧=開(読み込みの状態 非表示=N件)` は、表示するカレンダーの一覧の開閉と、非表示のカレンダーの数である。`key escape` のあとの `直近のEsc=` は、閉じたもの（`closeDetail`、`closeCalendarFilter`）か、パネルを閉じる動作（`closePanel`）を示す。状態の要約だけで判断せず、必ず PNG を見る
5. 判断してから次の操作を送る。複数の操作を 1 回の Bash 呼び出しにまとめない。`cd`、`sleep`、シェル変数、`&&` と `;` による連結も使わない
6. 終わったら `send .playwright/ui "quit"` で `serve` を止める。止まらなければプロセスを終了する

### コマンド

座標は PNG ではなく View のポイントで、左上が原点である。PNG の画素は `scale` 倍なので、PNG 上の座標を `scale` で割る。操作のたびに表示が落ち着くまで待ってから、`<ディレクトリ>/NNN-<操作名>.png` を書く。

| コマンド | 内容 |
| --- | --- |
| `click <x> <y>` | mouseMoved、mouseDown、mouseUp を送る |
| `hover <x> <y>` | mouseMoved を送る |
| `scroll <x> <y> <dy> [trackpad\|wheel\|fling\|drag]` | `dy` の符号は `NSEvent.scrollingDeltaY` と同じで、負で一覧が先へ進む。`trackpad`（既定）は精密な連続スクロールの began、changed、ended と、慣性の momentum を送る。`wheel` は精密でない 1 回のホイールで、`dy` は行数である。`fling` と `drag` は性能の計測に使う。`fling` は 120Hz の 1 フレームごとに、指が触れている間の 8 個のイベントと、0.94 倍ずつ減る慣性のイベントを送る。合成した慣性のイベントは `NSScrollView` に反映されないので、慣性の区間の重さを測るときは `drag` を使う。`drag` は同じ変化量の並びを、すべて指が触れたままのイベントとして送り、合計でおよそ `dy` だけ動く |
| `key escape|cmd+1|cmd+2` | Esc、⌘1、⌘2 の keyDown と keyUp を送る。⌘1 が月表示、⌘2 がコンパクト表示 |
| `wait <ms>` | 待ってから撮る |
| `chain <コマンド> ; <コマンド> ...` | 最後のコマンドの前の操作では、表示が落ち着くまで待たず、PNG も撮らずに次へ進む。操作の直後の操作（日を選んだ直後のスクロール、大きなスクロールの直後の「今日」）を再現するために使う。間を空けるときは `wait <ms>` を挟む。結果の 1 行と PNG は最後のコマンドのもの。通常の AIUI テストの 1 操作ずつの確認には使わず、タイミングに依存する不具合の再現にだけ使う |
| `hide` / `show` | パネルを隠して出し直す。`hide` はアプリの `MenuBarController.close` と同じ `orderOut`、`show` は同じインスタンスを出し直す。アプリは `orderFrontRegardless` と `makeKey` で出すが、操作ツールは完全に透明・背面・key にしない設定を保つため `orderBack` で出す。ウインドウが隠れたときと出たときの処理（先に用意した画像を捨てる、出た直後の先の用意）を再現する。性能の計測では `chain hide ; wait 300 ; show ; wait 3500 ; scroll ... drag` のように使う |
| `placement <user\|single> <x> <y> [compact]` | 仮想のディスプレイの配置（`user` は利用者の 3 枚、`single` は 1 枚。座標は画面座標で左下原点）とクリックの位置から、パネルのフレームを返す。ウインドウは作らず、何も出さない |
| `screenshot <名前>` | 操作せずに撮る |
| `quit` | `serve` を止める |

`fling` と `drag` の結果の 1 行には、フレームの数 `frames`、フレームごとの CPU 時間の最大 `frameCpuMax` と 95 パーセンタイル `frameCpuP95`（ミリ秒）、経過時間が 1 フレームの間隔の 1.5 倍を超えたフレームの数 `late`、フレームごとの CPU 時間の列 `list` が入る。負荷や周波数でぶれる ms の代わりに比べられるよう、フレームごとの命令数（100 万単位）の最大 `frameInsMax` と列 `insList` も入る。ただし、操作ツールのウインドウは key にならないので `onContinuousHover` は届かない。カーソルが入ったときの先描きは、このツールでは再現されない。120Hz の 1 フレームは 8.3ms なので、`frameCpuMax` がこれを超えるフレームは描画が間に合っていない。

`cpu` は、その操作の処理にかかったプロセスの CPU 時間（`getrusage(RUSAGE_SELF)` の user と system の合計の差分。ミリ秒）である。範囲は、イベントを送り始めてから、表示が落ち着くまで待つ処理の前までで、PNG を撮る処理と落ち着くまで待つ処理は含まない。`cpuSettle` は、落ち着くまで待つ処理まで含めた値である。スクロールなどの重さを数値で比べるときに使う。

`serve` は、準備ができたときに出す `ready` の行に、起動時の初期化（ポップオーバーの組み立て、最初の読み込み、表示が落ち着くまでの待ち）の CPU 時間 `cpuInit` と、プロセスの起動からの合計 `cpuProcess` をミリ秒で出す。ポップオーバーを開くコストを比べるときに使う。`ready` の行は、`serve` を起動した Bash の出力に出る。

座標が範囲外、コマンドが不正なときは `error: ...` を返し、終了コードは 1 になる。

### 仕組みと制約

- 画面外の座標に置いたパネルでは `NSScrollView` がスクロールを反映しないため、ウィンドウは完全に透明（`alphaValue = 0`）、デスクトップより背面、マウスを通す（`ignoresMouseEvents`）にして、ディスプレイの範囲内に `orderBack` で置く。key にもアプリの前面化もしない
- マウスは `NSApp.sendEvent` から届ける。ローカルモニター（`NSEvent.addLocalMonitorForEvents`）も呼ばれる。AppKit のボタンは mouseDown の中で mouseUp を待つため、アプリ自身のキューに mouseUp を積んでから mouseDown を送る
- スクロールは `CGEvent` の scroll wheel（`scrollWheelEvent2`）に phase、momentum phase、連続かどうかを設定して `NSEvent(cgEvent:)` に変換する。`CGEvent` は post しない。スクロールの `CGEvent` はウィンドウ番号を保持せず `window` が nil になるため、`window` と位置だけを差し替えた `NSEvent` のサブクラスを `NSApp.sendEvent` に渡す。ローカルモニターとウィンドウの両方に届く
- キーは `windowNumber` のパネルへ `NSApp.sendEvent` が渡す（パネルは key にしない）。`window.sendEvent` を重ねて呼ぶと Esc が 2 回届く
- 操作ツールの処理はメインアクターの 1 つのジョブの中で動く。ランループを回すだけでは、アプリのメインアクターの Task（予定の読み込み、`Task.sleep` のあとの処理）が操作の終わりまで動かず、実際のアプリと違う順に処理が進む。待つ間は、ランループを 1ms ずつ回しては `Task.yield()` で順番を譲る
- 設定のウインドウ、メニューバーの項目、パネルの開閉と閉じ方（外のクリック、他のアプリの前面化、アイコンの再押下）は対象外である。実機で確かめる。見た目は `barlunari-snapshots` で確かめる

保存先は `.playwright/` 配下にします。`.playwright/` は `.gitignore` に入れておきます。

### 表示するカレンダーの一覧の操作

- 座標は、直前の結果の PNG（`scale=1.0` のとき PNG の画素がそのままポイント）から読む。月表示（1862x1100pt の 3 列）では、見出しの一覧のボタンは約 (914, 25)、開くと右の詳細の列（x が約 1490 から右）に、アカウントのチェックボックス、カレンダーのチェックボックスが縦に並ぶ。日の欄（x が約 1110 から 1490）の時間軸のブロックは x が約 1180 から 1480、y は PNG を見て決める（1 時間 48pt）。予定を押すと詳細の列に詳細が出て、日の欄のスケジュールはそのまま残る。詳細の閉じるボタン（xmark）は約 (1840, 18) で、`click` で空の状態に戻れる。`key escape` でも戻れる。座標は PNG を見て決める
- `click 918 26` で開き、チェックの `click` を続け、`key escape` か閉じるボタンで閉じる。1 つ切り替えても閉じない
- チェックボックスは `NSButton` なので、`click` が効く。SwiftUI の `Toggle` と、コンパクト表示の見出しの `.borderless` のボタンは、このツールの合成したクリックに反応しない（変更前の版でも、コンパクト表示の見出しのボタンは反応しなかった）。コンパクト表示の一覧は、月表示で開いてから `key cmd+2` で切り替えると確かめられる（表示モードを切り替えても一覧は閉じない）

## 実際のアプリのパネルの開閉を確かめる

操作ツールは `NSApp.run()` を通らないので、LaunchServices の起動条件（`open -j` で隠して起動するなど）を再現しない。実際のアプリのパネルの開閉は、自己確認モードで確かめる。

```sh
scripts/bundle.sh
open -g -j --env BARLUNARI_PANEL_SELF_CHECK=1 build/Barlunari.app
# アイコンの押下と同じ処理を 1 回行わせる。開いていれば閉じる
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("io.github.derushio.Barlunari.selfCheckToggle"), object: nil, userInfo: nil, deliverImmediately: true)'
/usr/bin/log show --last 2m --predicate 'subsystem == "io.github.derushio.Barlunari" AND category == "panel"' --style compact
```

- 自己確認モードのパネルは、完全に透明で、マウスを通し、key にならない。利用者の画面とフォーカスは変わらない
- ログの `open+0.3s visible=true occluded=false` で、パネルが画面に出たことを確かめる。`wasHidden` は、開く前にアプリが隠されていたか
- 確かめ終えたら、環境変数なしで `open -g -j build/Barlunari.app` で起動し直す
- key になること、Esc、外のクリックで閉じること、フルスクリーンのアプリの上に出ることは、このモードでは確かめられない。利用者が実際に使ったときの panel カテゴリのログで確かめる

## 実行コマンド

```sh
swift test
swift test --filter <テスト名>
swift run barlunari-snapshots .playwright/snapshots
swift build --product barlunari-ui-driver
```
