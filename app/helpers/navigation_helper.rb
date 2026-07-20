module NavigationHelper
  # Areas declare a zero-argument route helper symbol; resolve it here so the
  # view never calls public_send directly.
  def navigation_area_path(area)
    public_send(area[:path_helper])
  end
end
