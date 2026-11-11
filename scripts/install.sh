#!/usr/bin/env bash
# scripts/bundle.sh で組み立てた Barlunari.app を /Applications に入れ、動いている Barlunari を終了させて起動し直す。
#
# 同じバンドル ID の .app が複数のパスにあると、LaunchServices が別のコピーを選ぶ。入れたあと build/Barlunari.app を
# LaunchServices の登録から外して削除し、/Applications のコピーだけを残す。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT="$ROOT/build/Barlunari.app"
DEST="/Applications/Barlunari.app"
# 名前が .app で終わらないので、LaunchServices はコピー中のバンドルをアプリとして登録しない。
STAGING="/Applications/.Barlunari.app.installing"
# Sources/BarlunariInfrastructure/AppIdentity.swift と同じ値にする。
BUNDLE_ID="io.github.derushio.Barlunari"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# worktree で組み立てた .app には別のバンドル ID が付き、利用者の許可と設定を引き継がない。main のチェックアウトでだけ入れる。
if [ "$(git -C "$ROOT" rev-parse --absolute-git-dir)" != "$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)" ]; then
    echo "worktree では /Applications に入れない。main のチェックアウトで実行する: $ROOT" >&2
    exit 1
fi

"$ROOT/scripts/bundle.sh"
built_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT/Contents/Info.plist")"
if [ "$built_id" != "$BUNDLE_ID" ]; then
    echo "バンドル ID が $BUNDLE_ID ではない: $built_id" >&2
    exit 1
fi

trap 'rm -rf "$STAGING"' EXIT
rm -rf "$STAGING"
# ditto は拡張属性とシンボリックリンクを保つ。入れ替える前に、コピーした .app の署名を確かめる。
ditto "$BUILT" "$STAGING"
codesign --verify --strict "$STAGING"

# このチェックアウトの build/Barlunari.app か /Applications/Barlunari.app から動いている Barlunari のプロセス ID を出す。
running_pids() {
    local pid exe
    for pid in $(pgrep -x Barlunari || true); do
        exe="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
        case "$exe" in
            "$DEST/Contents/MacOS/Barlunari" | "$BUILT/Contents/MacOS/Barlunari") echo "$pid" ;;
        esac
    done
}

# 動いているバンドルを置き換えると、動いているプロセスが古い実行ファイルと新しいリソースを混ぜて読む。先に SIGTERM で終了させる。
pids="$(running_pids)"
if [ -n "$pids" ]; then
    # shellcheck disable=SC2086 # プロセス ID ごとに引数にする。
    kill $pids
    for _ in $(seq 50); do
        [ -z "$(running_pids)" ] && break
        sleep 0.2
    done
    if [ -n "$(running_pids)" ]; then
        echo "Barlunari が 10 秒以内に終了しなかった: $(running_pids | tr '\n' ' ')" >&2
        exit 1
    fi
fi

rm -rf "$DEST"
mv "$STAGING" "$DEST"
"$LSREGISTER" -f "$DEST"
# 一度も起動していない build/Barlunari.app は LaunchServices に登録されておらず、-u は -10814 を出して 1 で終わる。
# 登録されていなければ外すものがないので、失敗しても続ける。
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
rm -rf "$BUILT"

open -g -j "$DEST"
for _ in $(seq 50); do
    [ -n "$(running_pids)" ] && break
    sleep 0.2
done
if [ -z "$(running_pids)" ]; then
    echo "$DEST が起動しなかった" >&2
    exit 1
fi
echo "入れて起動した: $DEST"
