require 'concerns/model_driven_api_application_record'
require 'concerns/model_driven_api_user'
require 'concerns/model_driven_api_role'

Rails.application.configure do
    config.after_initialize do
        # Fixes: https://stackoverflow.com/a/76781489
        ApplicationRecord.send(:include, ModelDrivenApiApplicationRecord)
        User.send(:include, ModelDrivenApiUser)
        Role.send(:include, ModelDrivenApiRole)
    end
end