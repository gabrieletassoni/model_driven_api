module ModelDrivenApi
  # Per-request state, reset by Rails after every request.
  class Current < ActiveSupport::CurrentAttributes
    # [class name, method name, reason] already logged as dropped from a/json_attrs.
    attribute :dropped_json_attrs
  end
end
