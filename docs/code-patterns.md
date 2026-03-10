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
            %th Actions
        %tbody
          - @things.each do |thing|
            %tr
              %td= thing.name
              %td
                = link_to thing, class: "btn-ghost btn-ghost-primary me-1", title: "Show" do
                  %span.material-symbols{style: "font-size: 18px"} visibility
                - if current_user.admin?
                  = link_to edit_thing_path(thing), class: "btn-ghost btn-ghost-secondary me-1", title: "Edit" do
                    %span.material-symbols{style: "font-size: 18px"} edit
                  = link_to thing, data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "btn-ghost btn-ghost-danger", title: "Delete" do
                    %span.material-symbols{style: "font-size: 18px"} delete
          - if @things.empty?
            %tr
              %td.text-muted.text-center{colspan: N} No things found.
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
      %dl.row.mb-0
        %dt.col-sm-3 Field
        %dd.col-sm-9= @thing.field

    .detail-section
      %h6.section-title Section Name
      %dl.row.mb-0
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

## Sidebar nav link
```haml
%li.nav-item
  = link_to things_path, class: "nav-link #{'active' if controller_name == 'things'}" do
    Things
```
