# Barlunari

Barlunari は、Google カレンダーなどの予定をメニューバーから確認する macOS アプリです。予定は EventKit で取得し、macOS の「インターネットアカウント」に追加したアカウントのカレンダーをまとめて表示します。SwiftUI と Swift Package Manager だけで作り、外部ライブラリは使いません。

仕様はコードが正です。別の仕様書は持ちません。このファイルには、コードを変えても変わらない規則だけを書き、実装の数値や型の一覧は書きません。

## コマンド

```sh
swift build                                        # ビルド
swift test                                         # 全テスト。ヘッドレスで実行されます
swift run barlunari-snapshots .playwright/snapshots # View を PNG に出力します。画面には表示しません
swift build --product barlunari-ui-driver           # AIUI テスト用の操作ツールをビルドします。使い方は headless-testing スキルです
scripts/bundle.sh                                  # build/Barlunari.app を組み立てます
scripts/install.sh                                 # 組み立てて /Applications に入れ、起動し直します。main のチェックアウトでだけ動きます
open -g -j <Barlunari.app のパス>                    # 起動確認。前面に出しません
```

## 守るルール

### レイヤーの依存の向き

依存の向きは `Package.swift` のターゲットで強制しています。依存関係を緩めて回避してはいけません。

```
BarlunariApp ──► Presentation ──► Application ──► Domain
      │                              ▲              ▲
      └────────► Infrastructure ─────┴──────────────┘
```

- Domain は Foundation だけに依存します
- Presentation は Infrastructure を参照しません。EventKit の型は Infrastructure の外に出しません
- 具象型の生成と依存の組み立ては `BarlunariApp` だけで行います。スナップショット、操作ツール、Presentation のテストは、Infrastructure を使わず、`BarlunariPreviewSupport` のフェイクで組み立てます
- ViewModel は、ユースケース、Application のポート、Presentation 内の型、`NotificationCenter` に依存します。Infrastructure の型とリポジトリには依存しません

### 新しいコードの置き場所

| 書くもの | 置き場所 |
| --- | --- |
| 不変条件を持つ値、同一性を持つ概念、業務ルール | `BarlunariDomain` |
| 利用者の操作 1 つに対応する処理、外部サービスのポート | `BarlunariApplication` |
| EventKit、UserDefaults、NSWorkspace、SMAppService の実装 | `BarlunariInfrastructure` |
| SwiftUI の View と `@Observable` の ViewModel | `BarlunariPresentation` |
| テストとスナップショット用のフェイク実装とサンプルデータ | `BarlunariPreviewSupport` |
| `@main` と依存の組み立て | `BarlunariApp` |

新機能は、ドメインから外側へ、Domain、Application、Infrastructure、Presentation、App の順に実装します。判断に迷うときは `ddd-architecture` スキルを読みます。

### 予定の取得とアカウント

- 予定は EventKit から取得します。アプリはアカウントの認証情報を持たず、アプリ内でアカウントを追加も削除もしません
- アカウントは `EKSource` の `sourceIdentifier` で同一視します。名前は表示だけに使います
- カレンダーと予定は、アカウントの ID と組にして同一視します。カレンダーや予定の ID だけで同一視しません
- 複数のアカウントが取得した同じ予定は、iCalendar の UID と日時が同じなら 1 件にします。UID を持たない予定は重複の判定に使いません
- カレンダーへのアクセスは完全アクセスを求めます。許可は、利用者が許可のボタンを押したときだけ求め、起動時には求めません
- 会議の URL は会議サービスのホストのものだけにし、判定は Infrastructure の 1 か所に集めます
- ログに予定の内容を出しません
- 変更通知での読み直しは、進行中の取得を取り消さず 1 回にまとめます。変更通知による読み直しでは、サーバーとの同期を求めません

### メニューバーの項目とパネル

- `MenuBarExtra` と `Settings` シーンは使いません。メニューバーの項目は `NSStatusItem`、パネルは `NSPanel` で出します
- パネルのフレームを書く処理は 1 か所にし、SwiftUI にウインドウをリサイズさせません
- `NSScreen.visibleFrame` の上端がメニューバーを除かないディスプレイがあります。メニューバーの下端は `visibleFrame` から求めません
- パネルの大きさに使う画面の領域は、パネルを出す側が View に渡します。View が画面を自分で読みません
- テストと操作ツールでは、パネルを前面に出さず、key にしません。`NSStatusItem` はテストで作りません
- メニューバーの項目は、対象の予定があれば次の予定までの残り時間を `HH:mm` で出し、なければアイコンを出します。対象は、残り時間の対象の判定で「対象」になり、開始が現在より後で、残りが 24 時間未満の予定のうち、自分が辞退していないものです。終日の予定の開始は、その日の 0:00 です。秒の端数は切り上げます。パネルを開かなくても動くよう、残り時間は `MenuBarCountdownViewModel` が自分で予定を取得してキャッシュします
- 予定を残り時間の対象にするかは、次の優先順位で決めます。判定は Domain の `CountdownTargetPolicy` が 1 か所で行い、`NextEventCountdown`、`UpcomingEvents`、`CountdownMark`、詳細の状態はこの型で判定します
  1. 予定ごとの選択。すべての予定の詳細のチェックボックスで、回ごとに選びます（`CountdownTargetSettings`、`countdownTargets`）
  2. カレンダーごとの設定。設定ウインドウの「残り時間」タブで、含めないカレンダーを選びます。含めないカレンダーの予定は対象外で、含めるカレンダーは 3 に進みます。新しいカレンダーは含めます（`CountdownCalendarSettings`、`countdownExcludedCalendars`）
  3. 既定。時刻付きは対象、終日は対象外です
- 予定ごとの選択とカレンダーごとの設定は、別の集約、別のリポジトリ、別の `UserDefaults` のキーで持ちます。カレンダーの設定を変えても、予定ごとの選択は消しません。辞退した予定は、どちらの設定にもかかわらず残り時間に数えません。チェックボックスは参加状況によらず出して操作でき、実際に数えるかの値を出します。予定のカレンダーを含めない設定にしているときは、チェックボックスの下に説明を出します。非表示のカレンダーは予定を取得しないので残り時間に数えず、「残り時間」タブではチェックボックスを無効にします
- `CountdownMark` は、予定ごとの選択が、その予定の既定の値（カレンダーの設定を含む）と違うときにだけ付けます。含めないカレンダーの予定に、一律には付けません

### スクロールと描画の性能

スクロール中の 1 フレームの CPU 時間を 8.3ms 以内に保ちます。release ビルドの `barlunari-ui-driver` の `scroll ... drag` で計測します。

- 月のマス目と予定一覧の範囲は最初に固定し、スクロールに合わせて広げたり、削ったり、作り直したりしません
- 予定は表示する範囲の全体を一度に取得し、スクロール、日の選択、月の移動では読み込み直しません
- 利用者のスクロールでは表示月だけを変え、選択日と詳細は変えません
- 行やセクションの View は、自分の分だけを ViewModel から読みます。親の View で全行分の配列を作りません
- マス目の行は `Canvas` で描き、マスや予定ごとに `Button` や View を作りません。`LazyVStack` や `VStack` に並べません
- 行への揃え（`scrollTargetBehavior(.viewAligned)`）を付けません
- マス目と予定一覧の View に、詳細、日の欄、カレンダーの一覧の開閉で変わる引数や環境の値を渡しません
- ポップオーバーのルートの body で、表示月や読み込みの状態を読みません

### 表示

- 表示モードは同期で保存し、最初の描画から保存したモードで出します
- 今日と選択日は、色だけでなく形でも区別します
- 辞退した予定は月のマス目に出さず、日の欄では薄い破線の枠で囲み、薄くして取り消し線を引きます。未回答の予定も破線の枠で囲むので、辞退した予定は線の種類だけでなく、薄さ、取り消し線、「辞退」の文字でも見分けられるようにします

### テスト

- テストは Swift Testing で書き、すべてヘッドレスで実行します
- 画面に表示するウィンドウを開く、フォーカスを奪う、カーソルを動かす操作は、テストでも手動確認でも行いません
- AppleScript や `cliclick` を使いません。アプリの起動確認は `open -g -j` で行います
- 見た目は `barlunari-snapshots` で PNG にして Read で開いて確かめます。`barlunari-snapshots` は、画面に出さないオフスクリーンの `NSWindow` に `NSHostingView` を入れて `cacheDisplay` で PNG にします。`setActivationPolicy(.prohibited)` を呼ぶので、前面にもキーにもならず、フォーカスを奪いません
- 詳細は `headless-testing` スキルを読みます

### コミット

- `main` ブランチで進め、小さく頻繁にコミットします
- Conventional Commits 形式で、説明は日本語にします。例は `feat(domain): CalendarDay を追加` です

### ship

- ship は、GitHub の `derushio/barlunari` の `main` へのマージと、`/Applications/Barlunari.app` への納品までを指します
- 納品は、マージのあと main のチェックアウトで `git pull` し、`scripts/install.sh` を実行して行います。`scripts/install.sh` は、動いている Barlunari を終了させて `/Applications/Barlunari.app` を置き換え、`build/Barlunari.app` を削除して、`/Applications/Barlunari.app` を起動し直します
- 常駐させるのは `/Applications/Barlunari.app` だけにします。main のチェックアウトの `build/Barlunari.app` は同じバンドル ID を持つので、残したり起動したりしません
- App Store には配信しません。App Store Connect への提出、公証、配布用の署名は行いません

### 文章と用語

- ユーザーに見せる文字列とドキュメントは日本語で書きます
- 型名と用語は既存のコードの名前に合わせます

## 参照

| 目的 | 参照先 |
| --- | --- |
| レイヤーの責務と新機能の追加手順 | `.claude/skills/ddd-architecture/SKILL.md` |
| テストの書き方とスナップショットの確認 | `.claude/skills/headless-testing/SKILL.md` |
| EventKit からの取得、許可、変換規則、会議の URL、重複の除去 | `.claude/skills/eventkit-integration/SKILL.md` |
| 利用者向けの案内 | `README.md` |
