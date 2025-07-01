# config/initializers/auto_include_json.rb

module AutoIncludeJson
  # Recursively builds a hash suitable for ActiveRecord eager loading
  def build_includes(include_option)
    Rails.logger.debug "AutoIncludeJson - Building includes from: #{include_option.inspect} from #{caller_locations(1,1).first.label}"
    case include_option
    when Array
      include_option.map { |item| build_includes(item) }
    when Hash
      include_option.each_with_object({}) do |(assoc, value), hash|
        # Skip keys that aren't associations
        next if [:only, :except, :methods].include?(assoc)

        if value.is_a?(Hash) && value[:include]
          hash[assoc] = build_includes(value[:include])
        elsif value.is_a?(Hash)
          # If value is a hash, assume it might contain nested structure
          nested = value.reject { |k, _| [:only, :except, :methods].include?(k) }
          hash[assoc] = build_includes(nested) unless nested.empty?
        else
          hash[assoc] = {} # eager load shallow association
        end
      end
    else
      []
    end
  end

  # Recursively sanitize include options to ensure only, except, methods propagate
  def sanitize_includes(include_option)
    case include_option
    when Array
      include_option
    when Hash
      include_option.each_with_object({}) do |(assoc, value), hash|
        hash[assoc] = {}

        if value.is_a?(Hash)
          hash[assoc][:only]    = value[:only] if value[:only]
          hash[assoc][:except]  = value[:except] if value[:except]
          hash[assoc][:methods] = value[:methods] if value[:methods]

          if value[:include]
            hash[assoc][:include] = sanitize_includes(value[:include])
          end
        end
      end
    else
      []
    end
  end
end

# For ActiveRecord::Relation (collections)
module AutoIncludeRelationJson
  include AutoIncludeJson

  def to_json(options = nil)
    Rails.logger.debug "AutoIncludeJson - Relation JSON to_json from #{caller_locations(1,1).first.label}"
    return super unless options.is_a?(Hash) && options[:include]

    includes_hash = build_includes(options[:include])
    sanitized_includes = sanitize_includes(options[:include])
    options = options.merge(include: sanitized_includes)

    self.includes(includes_hash).load.to_a.to_json(options)
  end

  def as_json(options = nil)
    Rails.logger.debug "AutoIncludeJson - Relation JSON as_json from #{caller_locations(1,1).first.label}"
    return super unless options.is_a?(Hash) && options[:include]

    includes_hash = build_includes(options[:include])
    sanitized_includes = sanitize_includes(options[:include])
    options = options.merge(include: sanitized_includes)

    self.includes(includes_hash).load.to_a.as_json(options)
  end
end

# For ActiveRecord::Base (single records)
module AutoIncludeInstanceJson
  include AutoIncludeJson

  def to_json(options = nil)
    preload_and_sanitize!(options)
    super
  end

  def as_json(options = nil)
    preload_and_sanitize!(options)
    super
  end

  private

  def preload_and_sanitize!(options)
    Rails.logger.debug "AutoIncludeJson - Instance JSON preload_and_sanitize! from #{caller_locations(1,1).first.label}"
    return unless options.is_a?(Hash) && options[:include]

    includes_hash = build_includes(options[:include])
    sanitized_includes = sanitize_includes(options[:include])
    options[:include] = sanitized_includes

    ActiveRecord::Associations::Preloader.new(
      records: [self],
      associations: includes_hash
    ).call
  end

end

# Activate extensions
ActiveRecord::Relation.prepend(AutoIncludeRelationJson)
ActiveRecord::Base.prepend(AutoIncludeInstanceJson)
