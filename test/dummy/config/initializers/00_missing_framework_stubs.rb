# Stub missing Rails framework config accessors so third-party engine initializers
# (e.g. thecore_background_jobs) don't blow up when action_mailbox / active_storage
# are not loaded in this api_only dummy app.
module MissingFrameworkStubs
  def action_mailbox
    @action_mailbox ||= ActiveSupport::OrderedOptions.new.tap do |o|
      o.queues = ActiveSupport::OrderedOptions.new
    end
  end

  def active_storage
    @active_storage ||= ActiveSupport::OrderedOptions.new.tap do |o|
      o.queues = ActiveSupport::OrderedOptions.new
    end
  end
end

Rails::Application::Configuration.prepend MissingFrameworkStubs
