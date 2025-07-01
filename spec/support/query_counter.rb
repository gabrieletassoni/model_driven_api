# spec/support/query_counter.rb
RSpec::Matchers.define :exceed_query_limit do |expected|
  supports_block_expectations

  match do |block|
    @count = count_queries(&block)
    @count > expected
  end

  failure_message do
    "expected to exceed #{expected} queries, but made #{@count}"
  end

  failure_message_when_negated do
    "expected not to exceed #{expected} queries, but made #{@count}"
  end

  def count_queries(&block)
    counter = 0
    callback = ->(_name, _start, _finish, _id, payload) do
      unless %w[SCHEMA CACHE].include?(payload[:name])
        counter += 1
      end
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    counter
  end
end
