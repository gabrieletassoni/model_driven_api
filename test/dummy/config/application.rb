require_relative "boot"

require "rails/all"

# Stub missing Rails framework config accessors so third-party engine initializers
# (e.g. thecore_background_jobs) don't blow up when action_mailbox / action_cable /
# assets etc. Those frameworks are not loaded in this api_only dummy app.
stub_class = Class.new do
  def method_missing(name, *args, &block)
    name_s = name.to_s
    # setters and predicates: no-op / false
    return false if name_s.end_with?("?")
    return nil   if name_s.end_with?("=") || args.any? || block
    # reader: return a nested stub so chained calls work
    ivar = :"@_s_#{name_s.gsub(/\W/, "_")}"
    instance_variable_get(ivar) || instance_variable_set(ivar, self.class.new)
  end
  # Do NOT implement to_ary — prevents implicit Array coercion that breaks
  # ActionMailer railtie's @paths.concat(config.action_mailer.mailers_paths).
  def respond_to_missing?(name, *) = name.to_s != "to_ary"
end

Rails::Application::Configuration.prepend(Module.new do
  # stub action_mailbox (not in bundle) and action_cable / assets (not needed for api_only).
  # Do NOT stub action_mailer — actionmailer gem is in the bundle and its railtie
  # needs config.action_mailer.preview_paths to be a real Array, not a proxy stub.
  %i[action_mailbox action_cable assets].each do |fw|
    define_method(fw) { instance_variable_get(:"@_stub_#{fw}") || instance_variable_set(:"@_stub_#{fw}", stub_class.new) }
  end
end)

Bundler.require(*Rails.groups)
require "model_driven_api"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.api_only = true

    dummy_root = File.expand_path("..", __dir__)
    config.autoload_paths  += Dir["#{dummy_root}/app/*/"]
    config.eager_load_paths += Dir["#{dummy_root}/app/*/"]

    # Ensure Ability is defined before engine after_initialize hooks include into it.
    initializer "dummy.missing_ar_macros", before: :run_load_hooks do
      # Stub Action Text macro — actiontext gem not installed in this api_only dummy.
      # Also stub rails_admin DSL macro — rails_admin gem not installed.
      ActiveSupport.on_load(:active_record) do
        extend(Module.new do
          def has_rich_text(*names)
            names.each { |name| define_method(name) { nil } }
          end
          def rails_admin(*args, &block); end
        end) unless respond_to?(:has_rich_text)
      end
    end

    initializer "dummy.preload_stubs", before: :run_load_hooks do
      require File.expand_path("../app/models/application_record", __dir__)
      require File.expand_path("../app/models/user", __dir__)
      require File.expand_path("../app/models/role", __dir__)
      require File.expand_path("../app/models/ability", __dir__)
      require File.expand_path("../app/channels/application_cable/connection", __dir__)
      require File.expand_path("../app/channels/application_cable/channel", __dir__)
      require File.expand_path("../app/jobs/application_job", __dir__)
    end

  end
end
