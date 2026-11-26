module Api
  # The API-hidden secrets of a model (host Odoo #6313, ADR 0006): its columns named like a secret
  # (Rails' filter_parameters convention) that the model already hides in some way: left out of its
  # default serializable_hash (Devise's encrypted_password), listed in its own json_attrs[:except]
  # (thecore_spot_overrides' encrypted_access_token), or declared in write_only_attributes. They are
  # never readable through the API: not in v3 attributes, not through v2 request options, not
  # through Ransack filters or sorts. A secret-named column the model doesn't hide stays readable.
  module HiddenSecrets
    # Names Rails treats as secrets, on top of the host's own filter_parameters.
    SECRET_NAMES = %i[passw secret token _key crypt salt certificate otp ssn cvv cvc].freeze

    module_function

    # Column names (Strings), memoized per class.
    def for(klass)
      return [] unless klass.is_a?(Class) && klass < ActiveRecord::Base && !klass.abstract_class?

      (@hidden ||= Concurrent::Map.new).compute_if_absent(klass) do
        write_only = klass.respond_to?(:write_only_attributes) ? Array(klass.write_only_attributes).map(&:to_s) : []
        hidden_columns = left_out_by_default(klass) | excepted_by_json_attrs(klass)
        # write_only_attributes are secrets by declaration, whatever their name.
        (hidden_columns.select { |column| secret_name?(column) } | write_only).freeze
      end
    end

    def secret_name?(name)
      @secret_filter ||= ActiveSupport::ParameterFilter.new(SECRET_NAMES + Rails.application.config.filter_parameters)
      @secret_filter.filter(name.to_s => "x")[name.to_s] != "x"
    end

    def left_out_by_default(klass)
      klass.column_names - klass.new.serializable_hash.keys
    rescue => e
      Rails.logger.warn("[model_driven_api] HiddenSecrets: #{klass.name}.new failed (#{e.class}), " \
                        "secrets hidden by its serializable_hash are not detected")
      []
    end

    def excepted_by_json_attrs(klass)
      attrs = klass.respond_to?(:json_attrs) ? klass.json_attrs : nil
      attrs.is_a?(Hash) ? Array(attrs[:except] || attrs["except"]).map(&:to_s) : []
    end
  end
end
