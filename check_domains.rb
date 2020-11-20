require 'slack/incoming/webhooks'
require 'pry'

WEBHOOK_URL = ENV["WEBHOOK_URL"]
CHECK_DOMAIN_PATH = "./check_domain/check_domain.sh"
CHECK_COMMAND = "#{CHECK_DOMAIN_PATH} -w 14 -c 7 -d "
CHECK_DOMAINS = File.open("domains","r").read

slack = Slack::Incoming::Webhooks.new WEBHOOK_URL
CHECK_DOMAINS.each_line {|line|
  result = `#{CHECK_COMMAND} #{line}`
  if ENV["WEBHOOK_URL"]
    slack.post result unless result =~ /^OK /
  else
    puts result
  end
}

