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

ActiveRecord::Schema[8.1].define(version: 2026_03_14_160000) do
  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "courses", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "course_group"
    t.string "course_no", null: false
    t.datetime "created_at", null: false
    t.integer "credits"
    t.string "department_code"
    t.boolean "is_gened", default: false, null: false
    t.boolean "is_thesis", default: false, null: false
    t.integer "l_credits"
    t.integer "l_hours"
    t.string "name", null: false
    t.string "name_abbr"
    t.string "name_th"
    t.integer "nl_credits"
    t.integer "nl_hours"
    t.bigint "program_id", null: false
    t.integer "revision_year", null: false
    t.integer "s_hours"
    t.datetime "updated_at", null: false
    t.index ["program_id"], name: "index_courses_on_program_id"
    t.index ["revision_year", "course_no"], name: "index_courses_on_revision_year_and_course_no", unique: true
  end

  create_table "data_imports", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.json "column_mapping"
    t.datetime "created_at", null: false
    t.integer "created_count", default: 0
    t.json "default_values"
    t.integer "error_count", default: 0
    t.text "error_message"
    t.string "mode", null: false
    t.json "row_errors"
    t.string "sheet_name"
    t.boolean "skip_failures", default: false, null: false
    t.string "state", null: false
    t.string "target_type", null: false
    t.integer "total_rows", default: 0
    t.datetime "updated_at", null: false
    t.integer "updated_count", default: 0
    t.bigint "user_id", null: false
    t.index ["state"], name: "index_data_imports_on_state"
    t.index ["target_type"], name: "index_data_imports_on_target_type"
    t.index ["user_id"], name: "index_data_imports_on_user_id"
  end

  create_table "programs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "degree_level", null: false
    t.string "degree_name", null: false
    t.string "field_of_study", null: false
    t.string "name_en", null: false
    t.string "name_th"
    t.datetime "updated_at", null: false
    t.integer "year_started", null: false
  end

  create_table "students", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "address"
    t.integer "admission_year", null: false
    t.datetime "created_at", null: false
    t.string "discord"
    t.string "email"
    t.string "enrollment_method"
    t.string "first_name", null: false
    t.string "first_name_th"
    t.date "graduation_date"
    t.string "guardian_name"
    t.string "guardian_phone"
    t.string "last_name", null: false
    t.string "last_name_th"
    t.string "line_id"
    t.string "phone"
    t.string "previous_school"
    t.bigint "program_id"
    t.string "status", default: "active", null: false
    t.string "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["admission_year"], name: "index_students_on_admission_year"
    t.index ["program_id"], name: "index_students_on_program_id"
    t.index ["student_id"], name: "index_students_on_student_id", unique: true
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_sign_in_at"
    t.string "line_link_token"
    t.datetime "line_link_token_expires_at"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.string "provider"
    t.string "role", default: "viewer", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["line_link_token"], name: "index_users_on_line_link_token", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "courses", "programs"
  add_foreign_key "data_imports", "users"
  add_foreign_key "students", "programs"
end
