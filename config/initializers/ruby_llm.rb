# API keys come from ENV only (see .env.example). They are optional at boot so
# CI, seeding and specs run without them; a call to a provider with no key
# raises RubyLLM::ConfigurationError at that point instead.
RubyLLM.configure do |config|
  config.gemini_api_key = ENV["GEMINI_API_KEY"].presence
  config.openai_api_key = ENV["OPENAI_API_KEY"].presence
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"].presence
end
