class RenameValidToIsValidInUsedToken < ActiveRecord::Migration[7.0]
  def change
    change_table :used_tokens, if_not_exists: true do |t|
      t.rename :valid, :is_valid
    end
  end
end
