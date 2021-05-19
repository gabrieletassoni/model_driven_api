class UsedToken < ApplicationRecord
  belongs_to :user, inverse_of: :used_tokens

  rails_admin do
    visible false
  end
end
