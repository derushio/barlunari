# Barlunari

Barlunari は、Google カレンダーなどの予定をメニューバーから確認する macOS アプリです。予定は EventKit で取得し、macOS の「インターネットアカウント」に追加したアカウントのカレンダーをまとめて表示します。SwiftUI と Swift Package Manager だけで作り、外部ライブラリは使いません。

仕様はコードが正です。別の仕様書は持ちません。このファイルには、コードを変えても変わらない規則だけを書き、実装の数値や型の一覧は書きません。

## コマンド

```sh
swift build                                        # ビルド
swift test                                         # 全テスト。ヘッドレスで実行されます
swift run barlunari-snapshots .playwright/snapshots # View を PNG に出力します。画面には表示しません
swift build --product barlunari-ui-driver           # AIUI テスト用の操作ツールをビルドします。使い方は headless-testing スキルです
scripts/bundle.sh                                  # .app を組み立てます
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

### メニューバーの項目とパネル

- `MenuBarExtra` と `Settings` シーンは使いません。メニューバーの項目は `NSStatusItem`、パネルは `NSPanel` で出します
- パネルのフレームを書く処理は 1 か所にし、SwiftUI にウインドウをリサイズさせません
- `NSScreen.visibleFrame` の上端がメニューバーを除かないディスプレイがあります。メニューバーの下端は `visibleFrame` から求めません
- パネルの大きさに使う画面の領域は、パネルを出す側が View に渡します。View が画面を自分で読みません
- テストと操作ツールでは、パネルを前面に出さず、key にしません。`NSStatusItem` はテストで作りません

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

### テスト

- テストは Swift Testing で書き、すべてヘッドレスで実行します
- 画面に表示するウィンドウを開く、フォーカスを奪う、カーソルを動かす操作は、テストでも手動確認でも行いません
- AppleScript や `cliclick` を使いません。アプリの起動確認は `open -g -j` で行います
- 見た目は `barlunari-snapshots` で PNG にして Read で開いて確かめます。`barlunari-snapshots` は、画面に出さないオフスクリーンの `NSWindow` に `NSHostingView` を入れて `cacheDisplay` で PNG にします。`setActivationPolicy(.prohibited)` を呼ぶので、前面にもキーにもならず、フォーカスを奪いません
- 詳細は `headless-testing` スキルを読みます

### コミット

- `main` ブランチで進め、小さく頻繁にコミットします
- Conventional Commits 形式で、説明は日本語にします。例は `feat(domain): CalendarDay を追加` です

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
