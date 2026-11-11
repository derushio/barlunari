#!/usr/bin/env bash
# 引数の .app を、Barlunari 専用の自己署名のコード署名用 ID で署名する。ID がなければ作る。
#
# ad-hoc 署名の指定要件は cdhash なので、組み立て直すたびにカレンダーの許可が外れる。同じ証明書で署名すると、指定要件が
# `identifier "<バンドル ID>" and certificate leaf = H"<証明書の SHA-1>"` になり、組み立て直しても許可が残る。
# ID は専用のキーチェーンに置く。ログインキーチェーンとキーチェーンの検索リストは変えない。
# ID を消すか作り直すと証明書の SHA-1 が変わり、許可は付け直しになる。
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "使い方: $0 <.app のパス>" >&2
    exit 64
fi
BUNDLE="$1"

DIR="$HOME/Library/Application Support/Barlunari Signing"
KEYCHAIN="$DIR/codesign.keychain-db"
PASSWORD_FILE="$DIR/keychain-password"
COMMON_NAME="Barlunari Local Code Signing"

identity_hash() {
    # 信頼設定をしないので、find-identity は CSSMERR_TP_NOT_TRUSTED を付けて出す。codesign は SHA-1 の指定で署名できる。
    security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
        | awk -v name="\"$COMMON_NAME\"" 'index($0, name) { print $2; exit }'
}

create_identity() {
    mkdir -p "$DIR"
    chmod 700 "$DIR"
    # 秘密鍵を含む一時ファイルは、失敗したときも終了時に消す。
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT

    # tr と head のパイプは、head が先に終わると tr が SIGPIPE で落ち、pipefail で失敗する。openssl rand を使う。
    openssl rand -hex 16 >"$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
    local password p12_password
    password="$(cat "$PASSWORD_FILE")"
    p12_password="$(openssl rand -hex 16)"

    cat >"$work/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $COMMON_NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    # 作り直すと許可が外れるため、期限で作り直す必要が出ないよう、有効期間を 20 年にする。
    openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/cert.cnf" \
        -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
    # OpenSSL 3 以降の既定の PKCS#12 の暗号は security import が読めない。-legacy で古い形式にする。
    # LibreSSL には -legacy がなく、既定で古い形式になる。
    local legacy=()
    if openssl version | grep -q '^OpenSSL [3-9]'; then legacy=(-legacy); fi
    openssl pkcs12 -export "${legacy[@]}" -inkey "$work/key.pem" -in "$work/cert.pem" \
        -name "$COMMON_NAME" -out "$work/identity.p12" -passout "pass:$p12_password"

    rm -f "$KEYCHAIN"
    security create-keychain -p "$password" "$KEYCHAIN"
    # 自動でロックしない設定にする。ロックは署名の前に毎回解除する。
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$password" "$KEYCHAIN"
    security import "$work/identity.p12" -k "$KEYCHAIN" -P "$p12_password" -T /usr/bin/codesign >/dev/null
    # codesign が鍵を使うときに、利用許可のダイアログを出さない。
    security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$KEYCHAIN" >/dev/null
}

if [ ! -f "$KEYCHAIN" ] || [ ! -f "$PASSWORD_FILE" ] || [ -z "$(identity_hash)" ]; then
    echo "コード署名用の ID を作成する: $KEYCHAIN" >&2
    create_identity
fi
security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
HASH="$(identity_hash)"
if [ -z "$HASH" ]; then
    echo "コード署名用の ID が見つからない: $KEYCHAIN" >&2
    exit 1
fi

codesign --force --sign "$HASH" --keychain "$KEYCHAIN" "$BUNDLE"
codesign --verify --strict --verbose=2 "$BUNDLE"
