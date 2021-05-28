class UsedToken < ApplicationRecord
  belongs_to :user, inverse_of: :used_tokens
end
