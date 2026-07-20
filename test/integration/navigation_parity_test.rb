require "test_helper"

# The sidebar (app/views/layouts/application.html.haml) and the home launchpad
# (Navigation::AREAS + Reports::Catalog) are two hardcoded lists of the same
# destinations. Driving both from one constant was considered and rejected - the
# sidebar renders live badge counts and multi-controller active states, which
# would need lambdas in the constant for the benefit of one caller.
#
# This test is what makes that duplication safe: add a sidebar item and forget
# home, and this fails.
class NavigationParityTest < ActionDispatch::IntegrationTest
  # Links that belong to the sidebar chrome and have no place on home.
  SIDEBAR_ONLY = [
    "/",  # the CP API brand link, which points at home itself
    "#"   # the account dropdown toggle
  ].freeze

  test "every sidebar destination also appears on the launchpad for an admin" do
    # Must run as an admin: a viewer's sidebar omits the whole admin block, so a
    # viewer-only run would never exercise the admin nav and would pass vacuously.
    assert_sidebar_parity(users(:admin))
  end

  test "every sidebar destination also appears on the launchpad for a viewer" do
    # Complements the admin case above. The admin run alone can't catch access-level
    # drift: give a main-nav AREAS entry a stray `access: :admin`, and the admin run
    # still passes while a viewer's sidebar keeps a link with no home counterpart.
    # A viewer's (smaller) sidebar is fully covered by their home page today, so
    # this is expected to pass, not just a placeholder for a future gap.
    assert_sidebar_parity(users(:viewer))
  end

  private

  def assert_sidebar_parity(user)
    post login_path, params: { username: user.username, password: "password123" }
    get root_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    sidebar_hrefs = doc.css("nav#sidebar a[href]").map { |a| a["href"] }.uniq - SIDEBAR_ONLY
    main_hrefs = doc.css("main a[href]").map { |a| a["href"] }.uniq

    assert sidebar_hrefs.any?, "found no sidebar links - the selector is wrong"

    missing = sidebar_hrefs - main_hrefs
    assert_empty missing,
                 "these sidebar destinations are missing from the home launchpad: " \
                 "#{missing.join(', ')}. Add them to Navigation::AREAS (or to " \
                 "SIDEBAR_ONLY if they are deliberately chrome-only)."
  end
end
