require 'concerns/model_driven_api_application_record'
require 'concerns/model_driven_api_user'
require 'concerns/model_driven_api_role'
require 'concerns/model_driven_api_push_subscriber'
require 'concerns/model_driven_api_push_message'

Rails.application.configure do
    config.after_initialize do
        # Fixes: https://stackoverflow.com/a/76781489
        ApplicationRecord.send(:include, ModelDrivenApiApplicationRecord)
        User.send(:include, ModelDrivenApiUser)
        Role.send(:include, ModelDrivenApiRole)
        PushSubscriber.send(:include, ModelDrivenApiPushSubscriber)
        PushMessage.send(:include, ModelDrivenApiPushMessage)
    end
end