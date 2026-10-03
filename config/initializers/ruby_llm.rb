# Provider keys live in Rails credentials, keyed by environment:
#
#   development:
#     GEMINI_API_KEY: ...
#   production:
#     GEMINI_API_KEY: ...
#
# An ENV variable of the same name overrides them (handy for CI, containers
# and one-off runs). Keys are optional at boot so specs, seeding and CI work
# without any; a provider call with no key raises RubyLLM::ConfigurationError.
RubyLLM.configure do |config|
  secret = ->(name) { ENV[name].presence || Rails.application.credentials.dig(Rails.env.to_sym, name.to_sym).presence }

  config.gemini_api_key = secret.call("GEMINI_API_KEY")
  config.openai_api_key = secret.call("OPENAI_API_KEY")
  config.anthropic_api_key = secret.call("ANTHROPIC_API_KEY")
end
