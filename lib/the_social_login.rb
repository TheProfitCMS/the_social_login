require 'the_social_login/version'
_root_ = File.expand_path('../../', __FILE__)

module TheSocialLogin
  class Engine < Rails::Engine; end
end

require "#{_root_}/app/models/concerns/social_networks_login_base"
