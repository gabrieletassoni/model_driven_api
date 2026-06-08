module Api
  module V3
    class SerializerFactory
      # Generate (and cache) a JSONAPI::Serializer subclass for model_class.
      #
      # nested_attrs: when set, use these attrs instead of model_class.json_attrs.
      #   Used for included associations — avoids reading the associated model's own
      #   json_attrs and prevents infinite recursion.
      # parent_name: when set, the generated constant is named
      #   "#{model_class.name}For#{parent_name}Serializer" and include: is NOT
      #   processed (one level deep only).
      def self.serializer_for(model_class, nested_attrs: nil, parent_name: nil)
        const_name = parent_name ? "#{model_class.name}For#{parent_name}Serializer" : "#{model_class.name}Serializer"
        return Api::V3.const_get(const_name) if Api::V3.const_defined?(const_name)

        jattrs = nested_attrs || (model_class.respond_to?(:json_attrs) ? (model_class.json_attrs || {}) : {})
        attr_set = Api::ResourceAttributeSet.for(model_class, jattrs: jattrs)

        # Nested serializers are always flat — no recursive includes — to prevent
        # infinite loops on circular associations (e.g. Role↔User).
        includes_map = parent_name ? {} : attr_set.parsed_includes

        type = model_class.model_name.plural.to_sym

        reflections = model_class.reflect_on_all_associations.each_with_object({}) { |r, h| h[r.name] = r }
        nested_info = includes_map.each_with_object({}) do |(assoc_name, assoc_spec), hash|
          reflection = reflections[assoc_name]
          next unless reflection
          nested_ser = assoc_spec \
            ? serializer_for(reflection.klass, nested_attrs: assoc_spec, parent_name: model_class.name) \
            : serializer_for(reflection.klass)
          hash[assoc_name] = { serializer: nested_ser, macro: reflection.macro }
        end

        klass = Class.new do
          include JSONAPI::Serializer
          set_type type
          attributes(*attr_set.attributes) if attr_set.attributes.any?

          attr_set.methods_list.each do |method_name|
            attribute(method_name) { |object| object.send(method_name) }
          end

          nested_info.each do |assoc_name, info|
            ser = info[:serializer]
            case info[:macro]
            when :has_many   then has_many   assoc_name, serializer: ser
            when :has_one    then has_one    assoc_name, serializer: ser
            when :belongs_to then belongs_to assoc_name, serializer: ser
            end
          end
        end

        Api::V3.const_set(const_name, klass)
        klass
      end

      # Parse json_attrs[:include] into { assoc_name => spec_or_nil }.
      # Delegates to Api::ResourceAttributeSet#parsed_includes.
      def self.extract_includes(include_spec)
        Api::ResourceAttributeSet.new([], [], include_spec).parsed_includes
      end
    end
  end
end
