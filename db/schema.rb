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

ActiveRecord::Schema[8.1].define(version: 2026_03_08_071512) do
  create_table "students", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "address"
    t.integer "admission_year", null: false
    t.datetime "created_at", null: false
    t.string "discord"
    t.string "email"
    t.string "enrollment_method"
    t.string "first_name", null: false
    t.string "first_name_th"
    t.string "guardian_name"
    t.string "guardian_phone"
    t.string "last_name", null: false
    t.string "last_name_th"
    t.string "line_id"
    t.string "phone"
    t.string "previous_school"
    t.string "status", default: "active", null: false
    t.string "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["admission_year"], name: "index_students_on_admission_year"
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
end
