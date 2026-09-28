domainsに記載されたドメインの期限をチェックするスクリプト。

期限の取得には自前の whois/RDAP プロキシ（Cloud Run）を使う。
`.jp` は whois.jprs.jp、それ以外は RDAP（IANA ブートストラップでレジストリを解決）。

## Usage

```
bundle
cp domains.example domains
vi domains

WHOIS_PROXY_URL=https://jp-whois-proxy-xxxxxxxx.asia-northeast1.run.app \
WHOIS_PROXY_KEY=<API_KEY> \
WEBHOOK_URL=<WEBHOOK_URL> \
bundle exec ruby check_domains.rb
```

`WEBHOOK_URL` を省略すると Slack へ送らず標準出力に出すだけになる。

## 環境変数

| 変数 | 既定値 | 内容 |
|---|---|---|
| `WHOIS_PROXY_URL` | （必須） | プロキシのベース URL |
| `WHOIS_PROXY_KEY` | （必須） | プロキシの API キー |
| `WEBHOOK_URL` | なし | Slack Incoming Webhook。未設定なら標準出力のみ |
| `DOMAINS_FILE` | `domains` | 対象一覧のパス |
| `WARN_DAYS` | `14` | 残日数がこれ以下で WARNING |
| `CRIT_DAYS` | `7` | 残日数がこれ以下で CRITICAL |
| `SLEEP_SEC` | `0.5` | 1件ごとの待ち時間 |

## domains の書式

1行1ドメイン。`#` 以降はコメントとして無視する。

```
groovenauts.co.jp
groovenauts.net
example.org   # 用途メモ
```

## 終了コード

Nagios 互換。全ドメインのうち最も悪い状態を返す。

| コード | 意味 |
|---|---|
| 0 | OK |
| 1 | WARNING |
| 2 | CRITICAL |
| 3 | UNKNOWN（取得失敗、未登録、TLD 未対応など） |

## Nagios プラグインからの移行

以前は `glensc/monitoring-plugin-check_domain` を submodule として持ち、
ホストの `whois` コマンド経由で期限を取得していた。以下が不要になった。

```
git submodule deinit -f check_domain
git rm -f check_domain
rm -rf .git/modules/check_domain
rm .gitmodules
```

`.jp` は権威 RDAP が存在せず、`whois` の出力形式もドメイン種別で異なる
（汎用JPは `[有効期限]`、属性型JPは `[状態] Connected (yyyy/mm/dd)`）。
この差異の吸収はプロキシ側に寄せてある。
