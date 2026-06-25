module ModelDrivenApiPushSubscriber
  extend ActiveSupport::Concern

  included do
    cattr_accessor :json_attrs
    self.json_attrs = ModelDrivenApi.smart_merge((json_attrs || {}), {
      include: {
        user: {
          only: %i[id email name surname]
        }
      }
    })
  end
end
