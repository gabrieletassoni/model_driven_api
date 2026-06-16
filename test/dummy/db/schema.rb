# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.
#
# Regenerate: cd test/dummy && RAILS_ENV=test bundle exec rake db:migrate db:schema:dump
# Sources: thecore_auth_commons, thecore_settings, model_driven_api (used_tokens),
#          activestorage (required by rails/all in dummy app)

ActiveRecord::Schema[7.2].define(version: 2025_12_16_111217) do
  enable_extension "plpgsql"

  create_table "actions", force: :cascade do |t|
    t.string "name"
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_actions_on_name", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ldap_servers", force: :cascade do |t|
    t.string "host", null: false
    t.integer "port", default: 389
    t.string "base_dn", null: false
    t.string "admin_user"
    t.string "admin_password"
    t.integer "priority", default: 1
    t.boolean "use_ssl", default: false
    t.string "auth_field", default: "userPrincipalName"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.string "surname"
    t.string "phone"
    t.string "code"
    t.index ["admin_password"], name: "index_ldap_servers_on_admin_password"
    t.index ["admin_user"], name: "index_ldap_servers_on_admin_user"
    t.index ["auth_field"], name: "index_ldap_servers_on_auth_field"
    t.index ["base_dn"], name: "index_ldap_servers_on_base_dn"
    t.index ["code"], name: "index_ldap_servers_on_code"
    t.index ["host"], name: "index_ldap_servers_on_host"
    t.index ["name"], name: "index_ldap_servers_on_name"
    t.index ["phone"], name: "index_ldap_servers_on_phone"
    t.index ["surname"], name: "index_ldap_servers_on_surname"
  end

  create_table "permission_roles", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "permission_id", null: false
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_permission_roles_on_permission_id"
    t.index ["role_id"], name: "index_permission_roles_on_role_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.bigint "predicate_id", null: false
    t.bigint "action_id", null: false
    t.bigint "target_id", null: false
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action_id"], name: "index_permissions_on_action_id"
    t.index ["predicate_id"], name: "index_permissions_on_predicate_id"
    t.index ["target_id"], name: "index_permissions_on_target_id"
  end

  create_table "predicates", force: :cascade do |t|
    t.string "name"
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_predicates_on_name", unique: true
  end

  create_table "role_users", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_role_users_on_role_id"
    t.index ["user_id"], name: "index_role_users_on_user_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "targets", force: :cascade do |t|
    t.string "name"
    t.bigint "lock_version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_targets_on_name", unique: true
  end

  create_table "thecore_settings", force: :cascade do |t|
    t.boolean "enabled", default: true
    t.string "kind", default: "string", null: false
    t.string "ns", default: "main"
    t.string "key", null: false
    t.text "raw"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_thecore_settings_on_key"
    t.index ["ns", "key"], name: "index_thecore_settings_on_ns_and_key", unique: true
  end

  create_table "used_tokens", force: :cascade do |t|
    t.string "token"
    t.bigint "user_id", null: false
    t.boolean "is_valid", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_used_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_used_tokens_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.boolean "admin", default: false, null: false
    t.bigint "lock_version"
    t.boolean "locked", default: false, null: false
    t.string "auth_source", default: "local", null: false
    t.index ["auth_source"], name: "index_users_on_auth_source"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "push_subscribers", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh"
    t.string "auth"
    t.string "user_agent"
    t.datetime "expired_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscribers_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscribers_on_user_id"
  end

  create_table "push_messages", force: :cascade do |t|
    t.bigint "push_subscriber_id", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "url"
    t.string "icon"
    t.datetime "sent_at"
    t.datetime "received_at"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["push_subscriber_id"], name: "index_push_messages_on_push_subscriber_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "permission_roles", "permissions"
  add_foreign_key "permission_roles", "roles"
  add_foreign_key "permissions", "actions"
  add_foreign_key "permissions", "predicates"
  add_foreign_key "permissions", "targets"
  add_foreign_key "role_users", "roles"
  add_foreign_key "role_users", "users"
  add_foreign_key "used_tokens", "users"
  add_foreign_key "push_messages", "push_subscribers"
end
