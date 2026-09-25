#!/usr/bin/env ruby
# frozen_string_literal: true

# domains に記載されたドメインの期限をチェックする。
#
# 期限の取得は check_domain (Nagios プラグイン) ではなく、自前の whois/RDAP プロキシに
# HTTP で問い合わせる。ホスト側の whois コマンドと git submodule は不要。
#
#   WHOIS_PROXY_URL=https://jp-whois-proxy-xxxxxxxx.asia-northeast1.run.app \
#   WHOIS_PROXY_KEY=xxxxx \
#   WEBHOOK_URL=https://hooks.slack.com/services/... \
#   bundle exec ruby check_domains.rb
#
# 終了コードは Nagios 互換 (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)。
# 全ドメインのうち最も悪いものを返す。

require 'date'
require 'json'
require 'net/http'
require 'uri'

OK       = 0
WARNING  = 1
CRITICAL = 2
UNKNOWN  = 3

LABEL = { OK => 'OK', WARNING => 'WARNING', CRITICAL => 'CRITICAL', UNKNOWN => 'UNKNOWN' }.freeze

def env!(name)
  value = ENV[name].to_s.strip
  abort "#{name} が設定されていません" if value.empty?
  value
end

PROXY_URL   = env!('WHOIS_PROXY_URL').sub(%r{/+\z}, '')
API_KEY     = env!('WHOIS_PROXY_KEY')
WEBHOOK_URL = ENV['WEBHOOK_URL'].to_s.strip
DOMAINS_FILE = ENV.fetch('DOMAINS_FILE', 'domains')

WARN_DAYS = Integer(ENV.fetch('WARN_DAYS', '14'))
CRIT_DAYS = Integer(ENV.fetch('CRIT_DAYS', '7'))
SLEEP_SEC = Float(ENV.fetch('SLEEP_SEC', '0.5'))

# ---------------------------------------------------------------------------

def request_expiration(domain)
  uri = URI.parse("#{PROXY_URL}/whois")
  uri.query = URI.encode_www_form(domain: domain)

  req = Net::HTTP::Get.new(uri)
  req['X-Api-Key'] = API_KEY
  req['Accept'] = 'application/json'

  Net::HTTP.start(uri.hostname, uri.port,
                  use_ssl: uri.scheme == 'https',
                  open_timeout: 10,
                  read_timeout: 40) { |http| http.request(req) }
end

# 一時的な失敗は1回だけ再試行する（コールドスタートや上流の瞬断）
def request_with_retry(domain, attempts: 2)
  last_error = nil

  attempts.times do |i|
    begin
      res = request_expiration(domain)
      return res unless res.is_a?(Net::HTTPServerError)

      last_error = "proxy #{res.code}"
    rescue StandardError => e
      last_error = e.message
    end
    sleep 3 if i < attempts - 1
  end

  raise last_error.to_s
end

def check(domain)
  res = begin
    request_with_retry(domain)
  rescue StandardError => e
    return [UNKNOWN, "UNKNOWN - #{domain} 問い合わせに失敗: #{e.message}"]
  end

  case res
  when Net::HTTPSuccess
    json = JSON.parse(res.body)
    expires = json['expiresOn']
    if expires.nil? || expires.empty?
      return [UNKNOWN, "UNKNOWN - #{domain} 有効期限が取得できませんでした (source=#{json['source']})"]
    end

    days = (Date.parse(expires) - Date.today).to_i
    if days.negative?
      [CRITICAL, "CRITICAL - #{domain} は #{-days} 日前に期限切れ (#{expires})"]
    elsif days <= CRIT_DAYS
      [CRITICAL, "CRITICAL - #{domain} の期限まで残り #{days} 日 (#{expires})"]
    elsif days <= WARN_DAYS
      [WARNING, "WARNING - #{domain} の期限まで残り #{days} 日 (#{expires})"]
    else
      [OK, "OK - #{domain} の期限まで残り #{days} 日 (#{expires})"]
    end

  when Net::HTTPNotFound
    [UNKNOWN, "UNKNOWN - #{domain} は登録が見つかりません（廃止済み、またはタイポ）"]
  when Net::HTTPUnauthorized
    [UNKNOWN, "UNKNOWN - #{domain} WHOIS_PROXY_KEY が不正です"]
  when Net::HTTPNotImplemented
    [UNKNOWN, "UNKNOWN - #{domain} の TLD は RDAP 未対応のため取得できません"]
  else
    [UNKNOWN, "UNKNOWN - #{domain} プロキシが #{res.code} を返しました: #{res.body.to_s[0, 120]}"]
  end
end

# ---------------------------------------------------------------------------

abort "#{DOMAINS_FILE} がありません" unless File.exist?(DOMAINS_FILE)

domains = File.readlines(DOMAINS_FILE)
               .map { |line| line.sub(/#.*\z/, '').strip.downcase }
               .reject(&:empty?)

abort "#{DOMAINS_FILE} にドメインがありません" if domains.empty?

worst = OK
problems = []

domains.each_with_index do |domain, i|
  status, message = check(domain)
  worst = status if status > worst
  problems << message unless status == OK
  puts message
  sleep SLEEP_SEC unless i == domains.size - 1
end

unless WEBHOOK_URL.empty? || problems.empty?
  require 'slack/incoming/webhooks'
  slack = Slack::Incoming::Webhooks.new WEBHOOK_URL
  slack.post(["ドメイン期限チェック: #{LABEL[worst]} (#{problems.size}/#{domains.size} 件)",
              *problems].join("\n"))
end

exit worst
