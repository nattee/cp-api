# Code Patterns

Canonical patterns for this project. Reference these instead of re-reading existing files.

## Controller (CRUD)

```ruby
class ThingsController < ApplicationController
  before_action :set_thing, only: %i[show edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]  # if admin-only writes

  def index
    @things = Thing.all
  end

  def show; end

  def new
    @thing = Thing.new
  end

  def create
    @thing = Thing.new(thing_params)
    if @thing.save
      redirect_to @thing, notice: "Thing was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @thing.update(thing_params)
      redirect_to @thing, notice: "Thing was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @thing.destroy!
    redirect_to things_path, notice: "Thing was successfully deleted."
  end

  private

  def set_thing
    @thing = Thing.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to things_path, alert: "Only admins can perform this action."
    end
  end

  def thing_params
    params.require(:thing).permit(:field1, :field2)
  end
end
```

## Views

### index.html.haml
```haml
.card{"data-controller" => "datatable"}
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Things
      - if current_user.admin?
        = link_to "New Thing", new_thing_path, class: "btn btn-primary btn-sm"
    .table-responsive
      %table.table.table-hover.mb-0{"data-datatable-target" => "table"}
        %thead
          %tr
            %th Column
            %th Status
            %th Actions
        %tbody
          - @things.each do |thing|
            %tr
              %td= thing.name
              %td
                %span.badge{class: "badge-#{thing.status.dasherize}"}= thing.status.titleize
              %td
                = link_to thing, class: "btn-ghost btn-ghost-primary me-1", title: "Show" do
                  %span.material-symbols{style: "font-size: 18px"} visibility
                - if current_user.admin?
                  = link_to edit_thing_path(thing), class: "btn-ghost btn-ghost-secondary me-1", title: "Edit" do
                    %span.material-symbols{style: "font-size: 18px"} edit
                  = link_to thing, data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "btn-ghost btn-ghost-danger", title: "Delete" do
                    %span.material-symbols{style: "font-size: 18px"} delete
          -# Do NOT add an empty-state row (colspan) inside a DataTable tbody.
          -# DataTables requires every <tr> to have exactly the same number of
          -# <td> cells as <th> headers. A colspan row breaks initialization.
          -# DataTables shows its own "No data available" message automatically.
```

### show.html.haml
```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1= @thing.name
  .d-flex.gap-2
    - if current_user.admin?
      = link_to "Edit", edit_thing_path(@thing), class: "btn btn-outline-secondary"
    = link_to "Back", things_path, class: "btn btn-outline-primary"

.card
  .card-body
    .detail-section
      %dl.dl-fields.row.mb-0
        %dt.col-sm-3 Field
        %dd.col-sm-9= @thing.field

    .detail-section
      %h6.section-title Section Name
      %dl.dl-fields.row.mb-0
        %dt.col-sm-3 Field
        %dd.col-sm-9= @thing.field
```

### _form.html.haml
```haml
= form_with(model: thing, class: "needs-validation") do |f|
  - if thing.errors.any?
    .alert.alert-danger
      %h5.alert-heading
        = pluralize(thing.errors.count, "error")
        prohibited this thing from being saved:
      %ul.mb-0
        - thing.errors.full_messages.each do |message|
          %li= message

  %fieldset.form-section
    %legend Section Name
    .row
      .col-md-6.mb-3
        = f.label :field, class: "form-label"
        .input-group
          %span.input-group-text
            %span.material-symbols icon_name
          = f.text_field :field, class: "form-control #{'is-invalid' if thing.errors[:field].any?}"
          - if thing.errors[:field].any?
            .invalid-feedback= thing.errors[:field].first

  = f.submit class: "btn btn-primary"
```

### new.html.haml
```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1 New Thing
  = link_to "Back", things_path, class: "btn btn-outline-primary"

.card
  .card-body
    = render "form", thing: @thing
```

### edit.html.haml
```haml
.d-flex.justify-content-between.align-items-center.mb-3
  %h1 Edit Thing
  = link_to "Back", thing_path(@thing), class: "btn btn-outline-primary"

.card
  .card-body
    = render "form", thing: @thing
```

## Fixtures
```yaml
thing_one:
  name: Example
  status: active
```
Users fixture uses ERB for password_digest:
```yaml
<% password_digest = BCrypt::Password.create("password123", cost: 4) %>
admin:
  username: admin_user
  password_digest: "<%= password_digest %>"
  role: admin
```

## Tests

### Model test pattern
```ruby
require "test_helper"

class ThingTest < ActiveSupport::TestCase
  test "valid thing" do
    thing = Thing.new(required_field: "value")
    assert thing.valid?
  end

  test "requires field" do
    thing = things(:thing_one).dup
    thing.field = nil
    assert_not thing.valid?
    assert_includes thing.errors[:field], "can't be blank"
  end
end
```

### Controller test (authorization)
```ruby
require "test_helper"

class ThingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    post login_path, params: { username: users(:viewer).username, password: "password123" }
  end

  test "non-admin cannot create" do
    assert_no_difference "Thing.count" do
      post things_path, params: { thing: { field: "value" } }
    end
    assert_redirected_to things_path
  end
end
```

### System test pattern
```ruby
require "application_system_test_case"

class ThingsTest < ApplicationSystemTestCase
  setup do
    visit login_path
    fill_in "Username", with: users(:admin).username
    fill_in "Password", with: "password123"
    click_on "Sign In"
  end

  test "index shows things" do
    visit things_path
    assert_text things(:thing_one).name
  end

  test "admin can create" do
    visit new_thing_path
    fill_in "Field", with: "Value"
    click_on "Create Thing"
    assert_text "Thing was successfully created"
  end

  test "admin can delete" do
    visit things_path
    accept_confirm do
      find("a[href='#{thing_path(things(:thing_one))}'][data-turbo-method='delete']").click
    end
    assert_text "Thing was successfully deleted"
  end
end
```

## Index Filters

Two patterns for filtering index pages, both using the `datatable` Stimulus controller.

### Client-side filters (radio buttons)

For small datasets where all rows are in the HTML. Uses regex column search on the
client — no server round-trip. Example: Staff index filtering by status/type.

```haml
.card{"data-controller" => "datatable", "data-datatable-page-length-value" => "50"}
  .card-body.p-3
    .d-flex.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Things
      .d-flex.align-items-center.gap-4.mx-auto
        .d-flex.align-items-center.gap-2
          %span.form-label.mb-0.small.text-muted Status
          .btn-group.btn-group-sm
            -# Each radio: value is a regex pattern, "" means show all.
            -# data-datatable-column-index: which table column to search.
            -# data-datatable-regex="true": treat value as regex.
            -# data-datatable-default-value: applied on page load (first checked radio).
            - [["Active", "^(?!.*Retired)"], ["All", ""]].each_with_index do |(label, value), i|
              - checked = i == 0
              %input.btn-check{type: "radio", name: "filter-status", id: "filter-status-#{i}", value: value, checked: checked, "data-datatable-target" => "filter", "data-action" => "change->datatable#filter", "data-datatable-column-index" => "3", "data-datatable-regex" => "true", "data-datatable-default-value" => (checked ? value : nil)}
              %label.btn.btn-outline-secondary{for: "filter-status-#{i}"}= label
```

### Server-side filters (Select2 dropdowns)

For large datasets using server-side DataTables. Select2 fires `change` → datatable
controller calls `column().search().draw()` → DataTables sends `columns[N][search][value]`
to the server endpoint. The server applies exact-match WHERE clauses.

**View:**
```haml
.card{"data-controller" => "datatable", "data-datatable-server-side-url-value" => datatable_things_path}
  .card-body.p-3
    .d-flex.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Things
      .d-flex.align-items-center.gap-4.mx-auto
        .d-flex.align-items-center.gap-2{style: "min-width: 320px"}
          %span.form-label.mb-0.small.text-muted Category
          -# "All" option has empty value — server skips empty filters.
          -# data-datatable-column-index must match the column order in thead.
          = select_tag "filter-category", options_for_select([["All", ""]] + @categories), data: { controller: "select2", datatable_target: "filter", action: "change->datatable#filter", datatable_column_index: "2" }
```

**Controller (datatable action):**
```ruby
# Read column-level search from DataTables server-side params
col_search = params.dig(:columns, "2", :search, :value).to_s.strip
base = base.where(category: col_search) if col_search.present?
```

## Inline CRUD (Turbo Frames)

For simple reference-data tables (e.g. Rooms) where separate new/edit pages feel heavy.
The form appears inline above the table; submit does a full page redirect.

**Why not Turbo Streams?** DataTables manages its own DOM — rows added via Turbo Streams
are invisible to it. A full page reload reinitializes DataTables naturally.

### Index view
```haml
.card{"data-controller" => "datatable"}
  .card-body.p-3
    .d-flex.justify-content-between.align-items-center.mb-3
      %h5.card-title.mb-0.fw-semibold.d-flex.align-items-center
        = resource_icon
        Things
      - if current_user.admin?
        = link_to new_thing_path, class: "btn btn-primary btn-sm", data: { turbo_frame: "thing_form" } do
          New Thing

    = turbo_frame_tag "thing_form"

    .table-responsive
      %table.table.table-hover.mb-0{"data-datatable-target" => "table"}
        -# ... table rows with edit links targeting "thing_form" ...
        -# = link_to edit_thing_path(thing), data: { turbo_frame: "thing_form" }
```

### new.html.haml / edit.html.haml
```haml
= turbo_frame_tag "thing_form" do
  .card.mb-3.border-primary
    .card-body.py-2.px-3
      %h6.card-title.mb-2 New Thing
      = render "form", thing: @thing
```

### _form.html.haml
```haml
-# data-turbo-frame="_top" makes the submit target the full page,
-# so the redirect refreshes the entire index (including DataTable).
-# Validation errors (422) also render at _top — acceptable trade-off.
= form_with(model: thing, data: { turbo_frame: "_top" }) do |f|
  -# ... form fields ...
  = f.submit class: "btn btn-primary btn-sm"
  = link_to "Cancel", things_path, class: "btn btn-outline-secondary btn-sm"
```

### Controller
```ruby
# No layout: false needed — Turbo Frame links extract just the frame
# from the full response automatically.
def new
  @thing = Thing.new
end

def create
  @thing = Thing.new(thing_params)
  if @thing.save
    redirect_to things_path, notice: "Thing was successfully created."
  else
    render :new, status: :unprocessable_entity
  end
end
```

## Sidebar nav link
```haml
%li.nav-item
  = link_to things_path, class: "nav-link #{'active' if controller_name == 'things'}" do
    Things
```

## Nested Fields (dynamic add/remove)

For `accepts_nested_attributes_for` with dynamic rows. Uses `nested_fields_controller.js` Stimulus controller.

**Multi-level nesting**: Each level uses a different placeholder (`NEW_RECORD`, `NEW_TIME_SLOT`, `NEW_TEACHING`). The controller's `placeholderValue` is configurable per instance.

```haml
-# Parent level (e.g. sections)
%fieldset{"data-controller" => "nested-fields", "data-nested-fields-wrapper-selector-value" => ".section-fields"}
  %div{"data-nested-fields-target" => "container"}
    - parent.children.each_with_index do |child, i|
      = f.fields_for :children, child, child_index: i do |cf|
        = render "child_fields", f: cf
  %template{"data-nested-fields-target" => "template"}
    = f.fields_for :children, Child.new, child_index: "NEW_RECORD" do |cf|
      = render "child_fields", f: cf
  %button{type: "button", "data-action" => "nested-fields#add"} Add

-# Sub-level inside child_fields partial (e.g. time slots inside sections)
.child-fields{"data-controller" => "nested-fields", "data-nested-fields-placeholder-value" => "NEW_SUB_RECORD", "data-nested-fields-wrapper-selector-value" => ".sub-fields"}
  -# Same template/container pattern with NEW_SUB_RECORD placeholder
```

Key points:
- `<template>` content is inert — inner templates work correctly when outer is cloned
- Select2 auto-connects on dynamically inserted elements (Stimulus MutationObserver)
- No `reject_if: :all_blank` — let validations show errors for explicitly added blank rows

## Week Calendar

Shared partial for schedule reports. Server-rendered CSS grid with absolute-positioned blocks.

```haml
= render "shared/week_calendar", entries: @entries
```

Each entry is a hash:
```ruby
{
  day_of_week: 1,           # 0=Sun..6=Sat
  start_time: "09:00",      # HH:MM string
  end_time: "10:30",
  label: "2110101",         # primary text (bold)
  sublabel: "Sec 1",        # secondary text
  detail: "ENG4-303",       # tertiary text (dimmed)
  color_key: "2110101",     # determines block color from 12-color palette
  url: "/course_offerings/5", # optional — wraps block in <a>
  badge: "<span>...</span>"   # optional raw HTML, positioned top-right
}
```

## CSV Export

Service class pattern for generating downloadable CSV.

```ruby
# app/services/exporters/foo_exporter.rb
module Exporters
  class FooExporter
    def initialize(scope)
      @scope = scope
    end

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS
        build_rows.each { |row| csv << row }
      end
    end

    def filename
      "foo_#{@scope.id}.csv"
    end
  end
end

# Controller action
def export
  exporter = Exporters::FooExporter.new(@thing)
  send_data exporter.to_csv, filename: exporter.filename, type: "text/csv", disposition: "attachment"
end
```
