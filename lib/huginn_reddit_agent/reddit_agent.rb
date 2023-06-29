module Agents
  class RedditAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Reddit Agent interacts with Reddit API.

      `debug` is used for verbose mode.

      `subreddit` is for hottest post (use space to separate subreddits).

      `token` is mandatory for auth endpoints.

      `type` is for the wanted action like read_unreadmessage.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

          {
            "kind": "t4",
            "data": {
              "first_message": XXXXXXXXXX,
              "first_message_name": "XXXXXXXXXX",
              "subreddit": "huginn",
              "likes": null,
              "replies": "",
              "author_fullname": null,
              "id": "XXXXXXX",
              "subject": "re: [join] I would like to join huginn",
              "associated_awarding_id": null,
              "score": 0,
              "author": null,
              "num_comments": null,
              "parent_id": "XXXXXXXXXX",
              "subreddit_name_prefixed": "r/huginn",
              "new": true,
              "type": "unknown",
              "body": "You're approved - welcome to the sub!",
              "dest": "hihouhou",
              "was_comment": false,
              "body_html": "&lt;!-- SC_OFF --&gt;&lt;div class=\"md\"&gt;&lt;p&gt;You&amp;#39;re approved - welcome to the sub!&lt;/p&gt;\n&lt;/div&gt;&lt;!-- SC_ON --&gt;",
              "name": "t4_1vxz7ox",
              "created": 1686931931,
              "created_utc": 1686931931,
              "context": "",
              "distinguished": "moderator"
            }
          }
    MD

    def default_options
      {
        'type' => 'read_unreadmessage',
        'debug' => 'false',
        'token' => '',
        'subreddit' => '',
        'limit' => '',
        'emit_events' => 'true',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :type, type: :array, values: ['read_unreadmessage', 'hottest_post_subreddit']
    form_configurable :token, type: :string
    form_configurable :limit, type: :string
    form_configurable :subreddit, type: :string
    form_configurable :debug, type: :boolean
    form_configurable :emit_events, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    def validate_options
      errors.add(:base, "type has invalid value: should be 'read_unreadmessage' 'hottest_post_subreddit'") if interpolated['type'].present? && !%w(read_unreadmessage hottest_post_subreddit).include?(interpolated['type'])

      unless options['subreddit'].present? || !['hottest_post_subreddit'].include?(options['type'])
        errors.add(:base, "subreddit is a required field")
      end

      unless options['token'].present? || !['read_unreadmessage', 'hottest_post_subreddit'].include?(options['type'])
        errors.add(:base, "token is a required field")
      end

      unless options['limit'].present? || !['hottest_post_subreddit'].include?(options['type'])
        errors.add(:base, "limit is a required field")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      if options.has_key?('details') && boolify(options['details']).nil?
        errors.add(:base, "if provided, details must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private

    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "body"
        log body
      end

    end

    def read_all_messages(base_url)

      uri = URI.parse("#{base_url}/api/read_all_messages")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{interpolated['token']}"
      request["User-Agent"] = "huginn/1"

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

    end

    def fetch_hottest_post(base_url,subreddit)
      url = URI("https://www.reddit.com/r/#{subreddit}/hot.json?limit=#{interpolated['limit']}")
      req = Net::HTTP::Get.new(url)
      req["User-Agent"] = "huginn/1"

      res = Net::HTTP.start(url.hostname, url.port, use_ssl: true) do |http|
        http.request(req)
      end

      log_curl_output(res.code,res.body)

      payload = JSON.parse(res.body)
      payload['data']['children'].each do |message|
        create_event payload: message
      end

    end

    def check_hottest_post_subreddit(base_url)
      subreddit_list = interpolated['subreddit'].split(" ")
      subreddit_list.each do |wanted_subreddit|
        fetch_hottest_post(base_url,wanted_subreddit)
      end

    end

    def check_unreadmessage(base_url)

      uri = URI.parse("#{base_url}/message/unread")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{interpolated['token']}"
      request["User-Agent"] = "huginn/1"

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      payload['data']['children'].each do |message|
        if interpolated['emit_events'] == 'true'
          create_event payload: message
        end
      end
      if !payload['data']['children'].empty?
        read_all_messages(base_url)
      end
    end

    def trigger_action

      base_url = 'https://oauth.reddit.com'
      case interpolated['type']
      when "read_unreadmessage"
        check_unreadmessage(base_url)
      when "hottest_post_subreddit"
        check_hottest_post_subreddit(base_url)
      else
        log "Error: type has an invalid value (#{interpolated['type']})"
      end
    end
  end
end
