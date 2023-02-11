class CreateUsedTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :used_tokens, if_not_exists: true do |t|
      t.string :token
      t.references :user, null: false, foreign_key: true
      t.boolean :valid, default: true

      t.timestamps
    end
    add_index :used_tokens, :token, unique: true, if_not_exists: true
  end
end
