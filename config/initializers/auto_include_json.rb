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

  # What to preload and the options to serialize with. Options from the request (a / json_attrs)
  # preload only real associations of +klass+ and keep their marks (Api::V2::RequestJsonAttrs);
  # the code's own options go through build_includes / sanitize_includes as before.
  def includes_and_options(klass, options)
    if Api::V2::RequestJsonAttrs.marked?(options)
      [Api::V2::RequestJsonAttrs.preloads(klass, options[:include]), options]
    else
      [build_includes(options[:include]), options.merge(include: sanitize_includes(options[:include]))]
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

    includes_hash, options = includes_and_options(klass, options)

    self.includes(includes_hash).load.to_a.to_json(options)
  end

  def as_json(options = nil)
    Rails.logger.debug "AutoIncludeJson - Relation JSON as_json from #{caller_locations(1,1).first.label}"
    return super unless options.is_a?(Hash) && options[:include]

    includes_hash, options = includes_and_options(klass, options)

    self.includes(includes_hash).load.to_a.as_json(options)
  end
end

# For ActiveRecord::Base (single records)
module AutoIncludeInstanceJson
  include AutoIncludeJson

  def to_json(options = nil)
    super(preload_and_sanitize(options))
  end

  def as_json(options = nil)
    super(preload_and_sanitize(options))
  end

  private

  # Returns a sanitized copy of the options, never mutating them: Rails 8.1's JSON encoder hands
  # as_json a frozen options hash, and the caller's hash is often a model's shared json_attrs.
  def preload_and_sanitize(options)
    Rails.logger.debug "AutoIncludeJson - Instance JSON preload_and_sanitize from #{caller_locations(1,1).first.label}"
    return options unless options.is_a?(Hash) && options[:include]

    includes_hash, options = includes_and_options(self.class, options)

    ActiveRecord::Associations::Preloader.new(
      records: [self],
      associations: includes_hash
    ).call

    options
  end

end

# Activate extensions
ActiveRecord::Relation.prepend(AutoIncludeRelationJson)
ActiveRecord::Base.prepend(AutoIncludeInstanceJson)
