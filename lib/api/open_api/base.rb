module Api
  module OpenApi
    class Base
      def initialize(models, request)
        @models = models
        @request = request
      end

      private

      def compute_type(model, key)
        Rails.logger.debug "compute_type #{model} #{key}"
        # if it's a file, a date or a text, then return string
        instance = model.new
        # If it's a method, it is a peculiar case, in which we have to return "object" and additionalProperties: true
        return "method" if model.methods.include?(:json_attrs) && model.json_attrs && model.json_attrs.include?(:methods) && model.json_attrs[:methods].include?(key.to_sym)
        # If it's not the case of a method, then it's a field
        method_class = instance.send(key).class.to_s
        Rails.logger.debug "compute_type #{model} #{key} #{method_class}"
        method_key = model.columns_hash[key]

        # Not columns
        return nil if method_key.nil?
        return "object" if method_class == "ActiveStorage::Attached::One"
        return "array" if method_class == "ActiveStorage::Attached::Many" || method_class == "Array" || method_class.ends_with?("Array") || method_class.ends_with?("Collection") || method_class.ends_with?("Relation") || method_class.ends_with?("Set") || method_class.ends_with?("List") || method_class.ends_with?("Queue") || method_class.ends_with?("Stack") || method_class.ends_with?("ActiveRecord_Associations_CollectionProxy")

        # Columns
        case method_key.type
        when :json, :jsonb
          return "object"
        when :enum
          return "array"
        when :text, :hstore
          return "string"
        when :decimal, :float, :bigint
          return "number"
        end
        method_key.type.to_s
      end

      def integer?(str)
        true if Integer(str) rescue false
      end

      def number?(str)
        true if Float(str) rescue false
      end

      def datetime?(str)
        true if DateTime.parse(str) rescue false
      end

      def create_properties_from_model(model, dsl, remove_reserved = false)
        parsed_json = JSON.parse(model.new.to_json(dsl))
        parsed_json.keys.map do |k|
          type = compute_type(model, k)

          # Remove fields that cannot be created or updated
          if remove_reserved && %w( id created_at updated_at lock_version ).include?(k.to_s)
            nil
          elsif type == "method" && (parsed_json[k].is_a?(FalseClass) || parsed_json[k].is_a?(TrueClass))
            [k, { "type": "boolean" }]
          elsif type == "method" && parsed_json[k].is_a?(String) && number?(parsed_json[k])
            [k, { "type": "number" }]
          elsif type == "method" && parsed_json[k].is_a?(String) && integer?(parsed_json[k])
            [k, { "type": "integer" }]
          elsif type == "method" && parsed_json[k].is_a?(String) && datetime?(parsed_json[k])
            [k, { "type": "string", "format": "date-time" }]
          elsif type == "method"
            # Unknown or complex format returned
            [k, { "type": "object", "additionalProperties": true }]
          elsif type == "date"
            [k, { "type": "string", "format": "date" }]
          elsif type == "datetime"
            [k, { "type": "string", "format": "date-time" }]
          elsif type == "object" && (k.classify.constantize rescue false)
            sub_model = k.classify.constantize
            properties = dsl[:include].present? && dsl[:include].include?(k) ? create_properties_from_model(sub_model, dsl[:include][k.to_sym]) : create_properties_from_model(sub_model, {})
            [k, { "type": "object", "properties": properties }] rescue nil
          elsif type == "array" && (k.classify.constantize rescue false)
            sub_model = k.classify.constantize
            properties = dsl[:include].present? && dsl[:include].include?(k) ? create_properties_from_model(sub_model, dsl[:include][k.to_sym]) : create_properties_from_model(sub_model, {})
            [k, { "type": "array", "items": { "type": "object", "properties": properties } }] rescue nil
          else
            [k, { "type": type }]
          end unless type.blank?
        end.compact.to_h
      end
    end
  end
end
