domainsに記載されたドメインの期限をチェックするスクリプト。

## Usage

```
git submodule update --init
bundle
cp domains.example domains
vi domains
WEBHOOK_URL=<WEBHOOK_URL> bundle exec ruby check_domains.rb
```
