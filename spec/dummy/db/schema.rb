# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 0) do

  create_table "habtm_records", force: :cascade, stagehand: true do |t|
  end

  create_table "serialized_column_records", force: :cascade, stagehand: true do |t|
    t.text "tags", limit: 65535
  end

  create_table "source_records", force: :cascade, stagehand: true do |t|
    t.string   "name",            limit: 255
    t.integer  "counter",         limit: 4
    t.string   "type",            limit: 255
    t.integer  "user_id",         limit: 4
    t.integer  "attachable_id",   limit: 4
    t.string   "attachable_type", limit: 255
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "stagehand_commit_entries", force: :cascade, stagehand: :commit_entries do |t|
    t.integer  "record_id",  limit: 4
    t.string   "table_name", limit: 255
    t.string   "operation",  limit: 255, null: false
    t.integer  "commit_id",  limit: 4
    t.string   "session",    limit: 255
    t.datetime "created_at"
  end

  add_index "stagehand_commit_entries", ["commit_id"], name: "index_stagehand_commit_entries_on_commit_id", using: :btree
  add_index "stagehand_commit_entries", ["operation", "commit_id"], name: "index_stagehand_commit_entries_on_operation_and_commit_id", using: :btree
  add_index "stagehand_commit_entries", ["record_id", "table_name"], name: "index_stagehand_commit_entries_on_record_id_and_table_name", using: :btree

  create_table "target_assignments", force: :cascade, stagehand: true do |t|
    t.integer  "source_record_id", limit: 4
    t.integer  "target_id",        limit: 4
    t.integer  "counter",          limit: 4
    t.datetime "created_at",                 null: false
    t.datetime "updated_at",                 null: false
  end

  create_table "users", force: :cascade, stagehand: false do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

end
