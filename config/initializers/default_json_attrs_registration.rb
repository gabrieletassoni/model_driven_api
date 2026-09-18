require "concerns/model_driven_api_default_json_attrs"

# Registers the generic default `json_attrs` module (ADR 0001) into
# ThecoreBackendCommons's shared DefaultModuleRegistry so it is `include`d
# into every `ApplicationRecord` subclass as it is defined.
#
# Installed from `config.to_prepare` -- not `config.after_initialize` -- for
# the same reason `ThecoreBackendCommons::DefaultModuleRegistry.install!` is:
# Rails runs `to_prepare` callbacks *before* `eager_load!`, so the module must
# already be registered before eager loading defines every model class in
# production. `to_prepare` also re-runs on every class reload in development;
# `DefaultModuleRegistry.register` is idempotent for the same module object,
# so re-running this block on reload is safe.
Rails.application.configure do
  config.to_prepare do
    ThecoreBackendCommons::DefaultModuleRegistry.register(ModelDrivenApiDefaultJsonAttrs)
  end
end
