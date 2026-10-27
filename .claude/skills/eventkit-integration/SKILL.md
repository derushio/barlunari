---
name: eventkit-integration
description: EventKit からのカレンダーと予定の取得、カレンダーへのアクセスの許可、EventKitMapper による変換規則、会議の URL の判定、複数のアカウントが取得した同じ予定の重複の除去、システム設定の画面を開く操作を実装・修正・案内するときに使います。
---

# eventkit-integration

EventKit との連携はすべて `MenuDateInfrastructure` に閉じ込めます。仕様はコードが正です。

## 取得

- `EventKitCalendarStore` は actor で、`EKEventStore` を 1 つ持ちます。`CalendarRepository`、`CalendarEventRepository`、`CalendarAccessAuthorizer` を実装します。`AppContainer` が 1 つだけ作り、3 つのポートに渡します
- `EKEventStore`、`EKCalendar`、`EKEvent` は `Sendable` ではないため、actor の外へ出しません。外へ返すのは、`EventKitValues.swift` の値から `EventKitMapper` で変換したドメインの型だけです
- アカウントは `EKSource` です。`store.calendars(for: .event)` のカレンダーが持つ `EKSource` を、`sourceIdentifier` で重複を除いてアカウントにします。識別子か名前が空の `EKSource` は除きます。名前の順、同じ名前なら `AccountID` の順に並べます
- カレンダーは `EKCalendar` です。Google のアカウントだけでなく、iCloud やその他の CalDAV のアカウントのカレンダーも対象にします。EventKit からは、Google のアカウントを他の CalDAV のアカウントと確実に区別できないためです。表示しないカレンダーは設定で非表示にします
- 予定は `predicateForEvents(withStart:end:calendars:)` と `events(matching:)` で、指定された `UserCalendar.Identity` のカレンダーだけを対象に取得します
- 変換できないカレンダーと予定は除き、取得全体は失敗させません
- EventKit はカレンダー単位の取得の失敗を返しません。失敗を、カレンダー単位とアカウント単位に分けて扱いません
- 取得したカレンダーの数、予定の数、UID を持たない予定の数を `Log.calendar` に記録します。予定のタイトル、場所、メモ、URL は記録しません

## 許可

- `Info.plist` に `NSCalendarsFullAccessUsageDescription` を入れます。`scripts/bundle.sh` が書きます
- 完全アクセスを `requestFullAccessToEvents` で求めます。`EKEventStore.authorizationStatus(for: .event)` が `.fullAccess` なら `CalendarAuthorizationStatus.fullAccess`、`.notDetermined` なら `.notDetermined`、それ以外は `.denied` にします。書き込みだけの許可と制限は、予定を読めないため `.denied` です
- 許可が得られたら、許可の前に作った store が空の結果を返し続けないよう、`store.reset()` を呼びます
- 許可は、利用者がポップオーバーか設定画面の「カレンダーへのアクセスを許可」を押したときだけ求めます。起動時には求めません。ダイアログは、状態が `notDetermined` のときだけ出ます
- 完全アクセスでなければ、`accounts()`、`calendars()`、`events(in:calendars:)` は `CalendarAccessError.notDetermined` か `.denied` を投げます。ユースケースも同じ型で投げます。カレンダーが 1 つもないときは、`LoadAgendaUseCase` が `.noCalendars` を投げます
- 拒否のときは、`SystemSettingsDestination.calendarPrivacy` で「プライバシーとセキュリティ」のカレンダーを開くボタンを出します。カレンダーがないときは、`.internetAccounts` で「インターネットアカウント」を開くボタンを出します。開く操作は `OpenSystemSettingsUseCase` と `SystemSettingsOpener` を通し、`WorkspaceSystemSettingsOpener` が `NSWorkspace` で開きます
- `.app` は ad-hoc 署名のため、ビルドし直すと macOS が別のアプリとして扱い、カレンダーへのアクセスの許可をもう一度求めることがあります。利用者向けの説明は `README.md` に書きます

## 変更通知

- `EKEventStoreChanged` を受けたら、`EventKitCalendarStore` が `NotificationCenter.default` に `Notification.Name.calendarStoreDidChange` を送ります。通知の名前は Application で定め、接頭辞は `AppIdentity.bundleIdentifier` と同じです
- `CalendarPopoverViewModel` と `SettingsViewModel` が `calendarStoreDidChange` を購読し、予定とカレンダーを読み直します。ViewModel は EventKit を参照しません
- 購読は解放時に解除します

## 変換規則

変換は `EventKitMapper` に集めます。`EventKitCalendarStore` は、EventKit の型から `EventKitValues.swift` の値への写しと、取得の組み立てだけを行います。

- `AccountID` は `EKSource` の `sourceIdentifier`、`UserAccount.name` は `title` です
- `CalendarID` は `calendarIdentifier` です。同じ共有カレンダーでもアカウントごとに別の `calendarIdentifier` になるため、カレンダーの同一性は `AccountID` と `CalendarID` の組のままにします
- カレンダーの色は `cgColor` を sRGB に変換し、各成分を 0 から 255 に丸めます。色を取れないカレンダーは灰色 `#808080` にします
- `EventID` は、`eventIdentifier` と開始日時の UNIX 時刻の秒を `@` でつなぎます。繰り返しの予定はすべての回が同じ `eventIdentifier` を持つため、回の開始日時と組にして回を区別します。`eventIdentifier` を持たない予定は `calendarItemIdentifier` を使います
- `iCalendarUID` は `calendarItemExternalIdentifier` です。CalDAV のカレンダーでは iCalendar の UID になります
- 時刻付きの予定は `.timed` にします。終了が開始より前の予定は、長さ 0 として扱います。`DateInterval` は終了が開始より前だと異常終了するためです
- 終日予定は `.allDay` にします。EventKit の終日予定の `endDate` は、最終日の終わり（23:59:59）のことと、翌日の 0:00 のことがあります。開始より後の 0:00 ちょうどならその日を排他的な終了日にし、それ以外は `endDate` の日の翌日を終了日にします。終了が開始より前の予定でも、少なくとも 1 日にします。日付の計算には `DateProvider` の暦を使い、呼ぶたびに読みます
- 自分の出欠は、`attendees` のうち `isCurrentUser` の参加者の `participantStatus` から変換します。`accepted` は `accepted`、`declined` は `declined`、`tentative` は `tentative`、`pending` と `unknown` は `needsAction` です。`delegated`、`completed`、`inProcess` と、参加者がいない予定、自分が参加者にいない予定は `notApplicable` です
- タイトルがない予定は空文字列にします。場所は前後の空白を取り除き、空なら `nil` にします

## メモと参加者

- メモは `EKEvent.notes` です。Google が会議の情報として付ける区切り線で囲まれたブロックを取り除きます。区切り線は、前後の空白を除いて `-::~` で始まり `::-` で終わる行です。最初の区切り線から次の区切り線までを、両端の行を含めて取り除きます。対になる区切り線がなければ、本文を失わないよう取り除きません
- ブロックを取り除いた後、3 行以上続く空行（空白だけの行を含む）を 1 行の空行にまとめ、前後の空白を取り除きます。空なら `nil` にします。改行は LF にそろえます
- 会議の URL の判定は、ブロックを取り除く前のメモで行います。Google Meet のリンクはこのブロックの中にあるためです。判定の対象を変えません
- 参加者は `EKEvent.attendees` と `organizer` です。値は `EventKitParticipantValue` に写し、`EventKitMapper.participants(of:)` で `EventParticipant` にします
- メールアドレスは参加者の `url` が `mailto:` のときだけ使います。CalDAV のカレンダーでは、`url` にプリンシパルの URL が入ることがあり、その場合はメールアドレスなしの参加者にします
- 主催者を先頭に置き、続けて `attendees` の順に並べます。主催者が `attendees` にもいれば 1 人にまとめます。同じ参加者かは、メールアドレスが大文字小文字を除いて同じか、双方にメールアドレスがなければ名前が同じかで判定します。まとめるときは、参加者の側の出欠を使い、自分かはどちらかが自分なら自分とします。主催者の側に名前やメールアドレスがなければ、参加者の側で補います
- 名前もメールアドレスもない参加者は、予定の変換を失敗させずに除きます
- メモと参加者の内容は `Log.calendar` に出しません

## 会議の URL

- 予定の URL、場所、メモの順に探します。場所とメモは、文中の http と https の URL を現れた順に取り出します。末尾の `.,;:!?` は URL に含めません
- 候補のうち、最初の会議サービスの URL を会議の URL にします。会議サービスでない URL は飛ばして、次の候補を調べます
- 会議サービスの URL は、スキームが http か https で、ホストが次のいずれかのものです。大文字小文字は区別しません
  - `meet.google.com`
  - `zoom.us` と、そのサブドメイン
  - `teams.microsoft.com`
  - `teams.live.com`
  - `webex.com` のサブドメイン
- Google Meet のリンクは、予定の URL と会議の URL には入らず、予定のメモに Google が付けたブロックの中にあります。Zoom と Teams のリンクもメモにあることがあります
- 詳細の URL は、予定の URL が http か https で、会議の URL と違うときだけ持ちます
- URL を開く操作は `URLOpener` を通します。ViewModel から `NSWorkspace` を呼びません

## 重複の除去

- 祝日カレンダーと、複数のアカウントに招待された会議は、アカウントごとに別のカレンダーに入り、iCalendar の UID が同じになります
- 同じ予定の判定には、`CalendarEvent.SharedKey`、つまり `iCalendarUID` と `EventSchedule` の組を使います。繰り返しの予定はすべての回が同じ UID を持つため、日時と組にして回を区別します。UID を持たない予定は、重複の判定に使いません
- `AgendaBuilder` が、同じ `SharedKey` の予定のうち、アカウントの並び順で先の予定を残します。同じアカウントの中では、先に取得した予定を残します
- 重複の除去は、表示するカレンダーの絞り込みの後、辞退した予定の除外の前に行います
- 重複の除去が実機で効いているかは、`Log.calendar` の記録を `log` コマンドで確かめます

## テスト

- `EventKitMapper` は `EventKitEventValue` などの値を作って確かめます。`@testable import MenuDateInfrastructure` で内部の型を使います。`EKEventStore` に触れるテストは書きません。許可のダイアログを出すためです
- 終日予定の終了日、複数日の終日予定、終了が開始より前の予定、出欠の対応表、会議の URL の探す順、会議サービスでない URL を飛ばす場合、メモの URL の末尾の句読点を、分岐ごとにテストします
- メモは、ブロックの除去（複数、対になる区切り線がない場合を含む）、空行のまとめ、空のメモを `nil` にする場合を、参加者は、`mailto:` 以外の URL、名前もメールアドレスもない参加者、主催者のまとめ方（メールアドレスの大文字小文字、名前でのまとめ、出欠の引き継ぎ）を、分岐ごとにテストします
- 重複の除去は `AgendaBuilder` のテストで、SharedKey が同じ予定、UID を持たない予定、先のアカウントのカレンダーを非表示にした場合を確かめます
- 許可の状態とカレンダーの有無による案内は、`FakeCalendarAccessAuthorizer` と `InMemoryCalendarRepository` で再現します

## やってはいけないこと

- EventKit の型を Infrastructure の外に出す
- `EKEventStore` を複数作る。許可の状態と取得結果が食い違います
- 起動時に許可を求める
- アカウントの名前を `AccountID` に使う
- UID だけで同じ予定とみなす。繰り返しの予定の回が 1 件になります
- 予定のタイトル、場所、メモ、URL をログに出す
