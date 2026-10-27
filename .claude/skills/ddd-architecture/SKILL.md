---
name: ddd-architecture
description: MenuDate にコードを追加・変更するとき、新機能を実装するとき、型をどのレイヤーに置くか迷ったとき、エンティティ・値オブジェクト・集約・ドメインサービス・リポジトリ・ユースケース・ポートの使い分けを判断するときに使います。戦術的 DDD のレイヤードアーキテクチャの責務と依存規則を定めます。
---

# ddd-architecture

MenuDate は戦術的 DDD のレイヤードアーキテクチャで作ります。仕様はコードが正で、用語は既存のコードの名前に合わせます。

## レイヤーの責務と依存規則

| ターゲット | 責務 | 依存してよいもの |
| --- | --- | --- |
| `MenuDateDomain` | 業務ルールと不変条件。エンティティ、値オブジェクト、集約、ドメインサービス、リポジトリのプロトコル | Foundation だけ |
| `MenuDateApplication` | 利用者の操作 1 つに対応するユースケース、外部サービスのポート、`CalendarAccessError` | Domain |
| `MenuDateInfrastructure` | EventKit、UserDefaults、NSWorkspace、SMAppService の実装 | Domain, Application |
| `MenuDatePresentation` | SwiftUI の View と `@Observable` の ViewModel | Domain, Application |
| `MenuDatePreviewSupport` | インメモリのフェイクとサンプルデータ | Domain, Application |
| `MenuDateApp` | `@main` とコンポジションルート | Domain, Application, Infrastructure, Presentation |
| `menudate-snapshots` | View を PNG に出力する実行ファイル | Domain, Application, Presentation, PreviewSupport |
| `menudate-ui-driver` | ポップオーバーを 1 操作ずつ動かして PNG を出力する実行ファイル | Domain, Application, Presentation, PreviewSupport |

依存は `Package.swift` のターゲットの依存関係で強制しています。コンパイルエラーになる import を、依存関係を足して通してはいけません。置き場所を見直します。

## 型の判断基準

- 値オブジェクト: 同一性を持たず、値が同じなら同じものとして扱う型です。不変条件は生成時に検証し、違反したら `DomainError` を投げます。`CalendarDay`、`CalendarMonth`、`DayRange`、`AccountID`、`CalendarID`、`EventID`、`CalendarColor`、`EventSchedule`、`AttendanceStatus`、`EventParticipant`、`WeekTimeline` がこれに当たります。`EventParticipant` は、名前とメールアドレスのどちらかを必須にする不変条件を生成時に検証します。値に関する判定は値オブジェクトに持たせます。例は `EventSchedule` の `hasEnded` と `span` です
- エンティティ: 時間が経って属性が変わっても同じものとして追跡する型です。同一性を表す ID で等価性を判定します。`UserAccount` は `AccountID` で、`UserCalendar` は `AccountID` と `CalendarID` の組で、`CalendarEvent` は `AccountID`、`CalendarID`、`EventID` の組で判定します。アカウントの名前は変わりうるので、同一性に使いません。`CalendarID` だけでは、アカウントをまたいで区別できません
- 集約: 不変条件を守る整合性の境界です。外からは集約ルートの操作だけで状態を変えます。`CalendarVisibility` が集約ルートで、`hide(_:)`、`show(_:)`、`isVisible(_:)` で操作します。いずれも `UserCalendar.Identity` を受けます
- ドメインサービス: 1 つのエンティティや値オブジェクトに属さない業務ルールです。状態を持たず、入力から結果を計算します。`AgendaBuilder` がこれに当たり、日ごとの予定を作る `build` と、日ごとの色を求める `colorsByDay` を持ちます。iCalendar の UID と日時が同じ予定を 1 件にする重複の除去も `build` が行います
- リポジトリ: 集約やエンティティの取得と保存の抽象です。プロトコルは Domain に置き、実装は Infrastructure に置きます。`CalendarRepository`、`CalendarEventRepository`、`CalendarVisibilityRepository` があります。予定のリポジトリは `UserCalendar.Identity` の集合を受け取り、カレンダーのリポジトリはアカウントとカレンダーを返します。読んでから書き戻す更新は、`CalendarVisibilityRepository.update` のように、リポジトリが原子的に行います
- ユースケース: 利用者の操作 1 つを表す `struct` で、`func execute(...) async throws` を持ちます。リポジトリとポートを組み合わせ、業務ルールそのものは持ちません。`LoadAgendaUseCase`、`ListCalendarsUseCase`、`RequestCalendarAccessUseCase` などがあります。許可の状態の確認は、ユースケースが行います
- ポート: Application が必要とする外部サービスの抽象です。プロトコルは Application に置き、実装は Infrastructure に置きます。`CalendarAccessAuthorizer`、`SystemSettingsOpener`、`DateProvider`、`LaunchAtLoginService`、`URLOpener` があります。`EventKitValues.swift` の値のように、Infrastructure の内部だけで使う型は、Application のポートにしません

迷ったときの順序は次のとおりです。

1. 業務ルールか不変条件なら Domain です
2. Domain の型だけで表せない外部との取り決めなら Application のポートです
3. 外部 API の型や保存先に触れるなら Infrastructure です
4. 画面の状態や操作なら Presentation です

## 新機能を追加する手順

ドメインから外側へ実装します。各段階でテストを書き、小さくコミットします。

1. 用語を決める。既存のコードの名前に合わせる
2. Domain: 値オブジェクト、エンティティ、ドメインサービス、リポジトリのプロトコルを追加し、単体テストを書く
3. Application: ポートとユースケースを追加し、`MenuDatePreviewSupport` のフェイクでテストする
4. Infrastructure: プロトコルを実装する。外部の型は `EventKitValues.swift` のような値に写して閉じ込め、`EventKitMapper` のような変換でドメインの型にする。変換は値を作ってテストする
5. Presentation: ViewModel を追加し、PreviewSupport のフェイクで組み立ててテストする。View はロジックを持たせない。`menudate-snapshots` に追加して PNG で確認する
6. App: `AppContainer` で実装を組み立てる

## やってはいけないこと

- Domain に EventKit の型、UI の型を入れる
- アカウントを持たない `CalendarID` だけで、カレンダーや予定を同一視する
- アカウントの名前を同一性に使う
- 値オブジェクトを検証なしで作る。不正な値を作れる `init` を公開しない
- ViewModel から Infrastructure を参照する。ViewModel が依存してよいのは、ユースケース、Application のポートの `DateProvider` と `URLOpener`、Presentation 内の `DataChangeNotifier`、通知の購読に使う `NotificationCenter` です。リポジトリには依存しません
- View にロジックを書く
- ユースケースに業務ルールを書く。ルールは Domain に置きます
- Infrastructure の外に EventKit の型を出す。許可の状態は `CalendarAuthorizationStatus` に、失敗は `CalendarAccessError` に変換します
- エンティティの ID を持たせずに属性だけで同一視する
- 集約ルートを通さずに集約の内部状態を変える
- コンポジションルート以外で具象型を生成して依存を組み立てる。例外は、`menudate-snapshots` の `Fixture`、`menudate-ui-driver` の `Harness`、`MenuDatePresentationTests` の `Harness` だけです。この 3 つは PreviewSupport のフェイクで ViewModel を組み立てます
- 外部ライブラリを追加する
