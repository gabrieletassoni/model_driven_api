module SafeSqlExecutor
  def self.execute_select(query)
    # Validate the query
    validate_select_query(query)

    # Execute the query
    ActiveRecord::Base.connection.execute(query)
  end

  private

  def self.validate_select_query(query)
    sanitized_query = query.strip.gsub(/\s+/, " ").upcase

    # Allow SELECT or WITH...SELECT queries
    unless sanitized_query.match?(/^(WITH .+)?SELECT /)
      raise ArgumentError, "Only SELECT queries (including with CTEs) are allowed"
    end
  end
end