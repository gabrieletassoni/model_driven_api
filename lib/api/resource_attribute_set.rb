module Api
  ResourceAttributeSet = Struct.new(:attributes, :methods_list, :includes) do
    def self.for(model_class, jattrs: nil)
      jattrs ||= model_class.respond_to?(:json_attrs) ? (model_class.json_attrs || {}) : {}
      only = Array(jattrs[:only]).map(&:to_sym)
      if only.empty?
        except = Array(jattrs[:except]).map(&:to_sym)
        only = model_class.column_names.map(&:to_sym) - except
      end
      new(only.reject { |a| a == :id }, Array(jattrs[:methods]).map(&:to_sym), jattrs[:include])
    end

    # Parse json_attrs[:include] into { assoc_name => spec_or_nil }.
    # Handles both symbol items (:roles) and hash items (users: { only: [:id] }).
    def parsed_includes
      return {} unless includes
      Array(includes).each_with_object({}) do |item, hash|
        case item
        when Hash then item.each { |k, v| hash[k] = v }
        when Symbol then hash[item] = nil
        end
      end
    end
  end
end
