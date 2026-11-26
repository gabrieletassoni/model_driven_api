module Api
  module V2
    # Serialization options a client sends in the query string (`a`, alias `json_attrs`) replace the
    # model's own json_attrs, and Rails runs `send` on every `methods` name and `include` key. These
    # options follow conventions instead of lists (ADR 0006, host Odoo #6285):
    #
    # - `include` keeps only real associations of each record's class;
    # - attributes the class hides by default (column_names minus a new record's default
    #   serializable_hash, e.g. Devise's encrypted_password, LdapServer#admin_password) never come back;
    # - a `methods` name declared in the class's json_attrs[:methods] runs as before (a developer
    #   exposed it); a column or association reader (or `<assoc>_ids`) is a plain read; any other
    #   name must be public, not a callback of the class (host Odoo #6314), end in neither `!` nor
    #   `=`, take no required argument and be written in
    #   the host or in a thecore gem (a gem named thecore* or depending on one), and it runs under
    #   the read-only guard: if it writes, or raises, only that field is dropped.
    #
    # A dropped name is logged once per request and the response stays 200. Options built by the
    # code (a model's json_attrs, a custom action's @json_attrs) carry no MARK and are untouched.
    module RequestJsonAttrs
      MARK = :_from_request

      module_function

      # The client's options, with MARK at every level the serializer will read.
      def from_params(options)
        mark(options.deep_symbolize_keys)
      end

      def mark(options)
        options = options.merge(MARK => true)
        includes = normalize_includes(options[:include])
        options[:include] = includes.transform_values { |nested| mark(nested) } if options.key?(:include)
        options
      end

      def marked?(options)
        options.is_a?(Hash) && options[MARK]
      end

      # `include` as { assoc => options }, whatever form the client sent (symbol, string, array,
      # hash). Not ResourceAttributeSet#parsed_includes: that one reads the model's own json_attrs
      # (symbols, nil specs); request params arrive as strings and must come out as option hashes.
      def normalize_includes(include_option)
        case include_option
        when Hash then include_option.to_h { |k, v| [k.to_sym, v.is_a?(Hash) ? v.deep_symbolize_keys : {}] }
        when Array then include_option.each_with_object({}) { |i, h| h.merge!(normalize_includes(i)) }
        when String, Symbol then {include_option.to_sym => {}}
        else {}
        end
      end

      # The options Rails should serialize a record of +klass+ with, and the methods to evaluate
      # under the read-only guard.
      def for_class(klass, options)
        hidden = Api::HiddenSecrets.for(klass)
        rewritten = options.except(MARK)
        rewritten[:only] = Array(options[:only]).map(&:to_s) - hidden if options.key?(:only)
        rewritten[:except] = Array(options[:except]).map(&:to_s) | hidden
        if options.key?(:include)
          rewritten[:include] = normalize_includes(options[:include]).select do |name, _|
            next true if active_record?(klass) && klass.reflect_on_association(name)

            drop(klass, name, "not an association")
            false
          end
        end
        plain, guarded = [], []
        Array(options[:methods]).map(&:to_s).uniq.each do |name|
          case (kind = method_kind(klass, name))
          when :declared, :reader then plain << name
          when :guarded then guarded << name
          else drop(klass, name, kind)
          end
        end
        rewritten[:methods] = plain
        [rewritten, guarded]
      end

      # :declared, :reader, :guarded, or the reason it is refused (a String). Cached per class and
      # name, but only for names the class defines: the client chooses the names, so caching any
      # name would let it grow memory without bound.
      def method_kind(klass, name)
        return "not a public method" unless klass.method_defined?(name) || klass.private_method_defined?(name)

        (@method_kinds ||= Concurrent::Map.new).compute_if_absent([klass, name]) { classify(klass, name) }
      end

      def classify(klass, name)
        return "hidden attribute" if Api::HiddenSecrets.for(klass).include?(name)
        return :declared if declared_methods(klass).include?(name)
        return :reader if reader?(klass, name)
        return "ends in ! or =" if name.end_with?("!", "=")
        return "not a public method" unless klass.public_method_defined?(name)
        return "a callback" if callback?(klass, name)

        method = klass.instance_method(name)
        return "takes required arguments" if method.parameters.any? { |type, _| %i[req keyreq].include?(type) }
        return "not written in the app or a thecore gem" unless our_code?(method.source_location&.first)

        :guarded
      end

      def declared_methods(klass)
        return [] unless klass.respond_to?(:json_attrs) && klass.json_attrs.is_a?(Hash)

        Api::ResourceAttributeSet.for(klass).methods_list.map(&:to_s)
      end

      def active_record?(klass) = klass < ActiveRecord::Base

      # Registered as a Symbol filter in any of the class's callback chains (validation, validate,
      # save, create, update, destroy, commit, rollback, initialize, find, touch, and any custom
      # chain). A callback belongs to the record's lifecycle, never to its API, and its side
      # effects may live outside the database, where the read-only guard can't see them.
      def callback?(klass, name)
        return false unless klass.respond_to?(:__callbacks)

        klass.__callbacks.each_value.any? { |chain| chain.any? { |cb| cb.filter.is_a?(Symbol) && cb.filter.to_s == name } }
      end

      def reader?(klass, name)
        return false unless active_record?(klass)
        return true if klass.column_names.include?(name)
        return true if klass.reflect_on_association(name)

        klass.reflect_on_all_associations.any? { |r| r.collection? && "#{r.name.to_s.singularize}_ids" == name }
      end

      # Written in the host app or in a thecore gem. The gem that owns the file decides first:
      # deploy images install the bundle inside the app (/app/vendor/bundle), so "under Rails.root"
      # alone would make Rails, Devise and every other gem ours.
      def our_code?(file)
        return false if file.blank?

        owner = Gem.loaded_specs.values
          .select { |spec| file.start_with?(File.join(spec.full_gem_path, "")) }
          .max_by { |spec| spec.full_gem_path.length }
        return thecore_gem?(owner.name) if owner
        return false if gem_dirs.any? { |dir| file.start_with?(dir) }

        file.start_with?(File.join(Rails.root.to_s, ""))
      end

      # A gem named thecore* or depending, directly or not, on one. Memoized per gem name.
      def thecore_gem?(name, seen = Set.new)
        cache = (@thecore_gems ||= Concurrent::Map.new)
        return cache[name] if cache.key?(name)
        return false unless seen.add?(name) # a dependency cycle: decided by the other branches

        spec = Gem.loaded_specs[name]
        found = !spec.nil? &&
          (name.start_with?("thecore") || spec.runtime_dependencies.any? { |dep| thecore_gem?(dep.name, seen) })
        cache.put_if_absent(name, found)
        found
      end

      # Where gems live, even those no spec claims (default gems, a vendored bundle).
      def gem_dirs
        @gem_dirs ||= (Gem.path + [Bundler.bundle_path.to_s]).map { |dir| File.join(dir, "") }.uniq.freeze
      end

      # A name the client asked for that is not served: logged once per request.
      def drop(klass, name, reason)
        seen = (ModelDrivenApi::Current.dropped_json_attrs ||= Set.new)
        return unless seen.add?([klass.name, name, reason])

        Rails.logger.warn("[model_driven_api] a/json_attrs: #{klass.name}##{name} dropped (#{reason})")
      end

      # Prepended to ActiveModel::Serialization (records and the ActiveModel objects a custom action
      # may return): applies the conventions to marked options only.
      module Serialization
        def serializable_hash(options = nil)
          return super unless RequestJsonAttrs.marked?(options)

          rewritten, guarded = RequestJsonAttrs.for_class(self.class, options)
          hash = super(rewritten)
          guarded.each do |name|
            # A refused write may already have changed the record in memory (update_column does):
            # restore it so neither the next field nor the caller sees a value that was never saved.
            snapshot = @attributes.deep_dup if is_a?(ActiveRecord::Base)
            hash[name] = ActiveRecord::Base.while_preventing_writes { send(name) }
          rescue => e
            @attributes = snapshot if is_a?(ActiveRecord::Base)
            RequestJsonAttrs.drop(self.class, name, "raised #{e.class}")
          end
          hash
        end
      end

      # The associations of +klass+ worth preloading for marked options: real ones only, nested
      # through non-polymorphic reflections.
      def preloads(klass, include_option)
        normalize_includes(include_option).each_with_object({}) do |(name, nested), out|
          reflection = klass.reflect_on_association(name) or next
          out[name] = (reflection.polymorphic? || !nested.key?(:include)) ? {} : preloads(reflection.klass, nested[:include])
        end
      end
    end
  end
end
