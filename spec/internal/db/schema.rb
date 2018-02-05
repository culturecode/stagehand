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

  create_table "habtm_records", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: true do |t|
  end

  create_table "serialized_column_records", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: true do |t|
    t.text "tags", limit: 65535
  end

  create_table "source_records", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: true do |t|
    t.string   "name"
    t.integer  "counter"
    t.string   "type"
    t.integer  "user_id"
    t.string   "attachable_type"
    t.integer  "attachable_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["attachable_type", "attachable_id"], name: "index_source_records_on_attachable_type_and_attachable_id", using: :btree
    t.index ["user_id"], name: "index_source_records_on_user_id", using: :btree
  end

  create_table "stagehand_commit_entries", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: :commit_entries do |t|
    t.integer  "record_id"
    t.string   "table_name"
    t.string   "operation",  null: false
    t.integer  "commit_id"
    t.string   "session"
    t.datetime "created_at"
    t.index ["commit_id"], name: "index_stagehand_commit_entries_on_commit_id", using: :btree
    t.index ["operation", "commit_id"], name: "index_stagehand_commit_entries_on_operation_and_commit_id", using: :btree
    t.index ["record_id", "table_name"], name: "index_stagehand_commit_entries_on_record_id_and_table_name", using: :btree
  end

  create_table "target_assignments", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: true do |t|
    t.integer  "source_record_id"
    t.integer  "target_id"
    t.integer  "counter"
    t.datetime "created_at",       null: false
    t.datetime "updated_at",       null: false
    t.index ["source_record_id"], name: "index_target_assignments_on_source_record_id", using: :btree
    t.index ["target_id"], name: "index_target_assignments_on_target_id", using: :btree
  end

  create_table "users", force: :cascade, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci", stagehand: false do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

end
