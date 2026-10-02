module Admin
  # Everything under /admin changes what the assistant tells patients, so it
  # sits behind HTTP Basic auth (ADMIN_USER / ADMIN_PASSWORD).
  #
  # With no ADMIN_PASSWORD set, development and test are open for convenience;
  # every other environment stays locked.
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      expected_password = ENV["ADMIN_PASSWORD"].presence
      return if expected_password.nil? && Rails.env.local?

      authenticate_or_request_with_http_basic("Calma admin") do |user, password|
        expected_password.present? &&
          ActiveSupport::SecurityUtils.secure_compare(user, ENV.fetch("ADMIN_USER", "admin")) &
            ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
      end
    end
  end
end
