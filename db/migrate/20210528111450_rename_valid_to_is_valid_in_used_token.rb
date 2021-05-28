class RenameValidToIsValidInUsedToken < ActiveRecord::Migration[6.0]
  def change
    change_table :used_tokens do |t|
      t.rename :valid, :is_valid
    end
  end
end
