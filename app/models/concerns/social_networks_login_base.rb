module SocialNetworksLogin
  module Base
    extend ActiveSupport::Concern

    def self.networks_list
      %w[ vkontakte facebook twitter google_oauth2 odnoklassniki ]
    end


    included do
      attr_accessor :oauth_data

      has_many :credentials, dependent: :destroy

      before_validation :set_oauth_params,   on: :create, if: ->{ oauth? }
      before_validation :define_login,       on: :create, if: ->{ oauth? }
      before_validation :define_email,       on: :create, if: ->{ oauth? }
      before_validation :define_password,    on: :create, if: ->{ oauth? }
      before_save       :skip_confirmation!, on: :create, if: ->{ oauth? }

      after_save :create_credential,   if: ->{ oauth? }
      after_save :upload_oauth_avatar, if: ->{ oauth? }

      def set_oauth_params
        set_params_common_oauth
        set_params_from_tw_oauth if twitter_oauth?
        set_params_from_fb_oauth if facebook_oauth?
        set_params_from_vk_oauth if vkontakte_oauth?
        set_params_from_gp_oauth if google_oauth2_oauth?
        set_params_from_ok_oauth if odnoklassniki_oauth?
      end

      def default_email_domain
        'my-web-site.com'
      end

      def attempts_to_generate
        10
      end

      # do something common here
      def set_params_common_oauth
        self.username = info.try(:[], 'name')
      end

      # do something special here
      def set_params_from_gp_oauth
        self.gp_addr = info.try(:[], 'urls').try(:[], 'Google')
      end

      def set_params_from_fb_oauth
        self.fb_addr = info.try(:[], 'urls').try(:[], 'Facebook')
      end

      def set_params_from_vk_oauth
        self.vk_addr = info.try(:[], 'urls').try(:[], 'Vkontakte')
      end

      def set_params_from_tw_oauth
        self.tw_addr = info.try(:[], 'urls').try(:[], 'Twitter')
      end

      def set_params_from_ok_oauth
        self.ok_addr = info.try(:[], 'urls').try(:[], 'Odnoklassniki')
      end

      def create_credential_with_oauth(uid, provider, _credentials)
        exp_date = nil
        exp_date = (Time.now + _credentials['expires_at'].to_i.seconds) if !_credentials['expires_at'].blank?

        credentials_record = credentials.where(provider: provider).first

        unless credentials_record
          credentials_record = credentials.create(
            uid: uid,
            provider: provider,
            expires_at: exp_date,
            access_token: _credentials['token'],
            access_token_secret: _credentials['secret'] # twitter
          )

          SystemMessage.create_credentials_for_user(self, provider)
        end

        credentials_record
      end

      def update_social_networks_urls! omniauth
        info = omniauth.try(:[], 'info')

        self.gp_addr = info.try(:[], 'urls').try(:[], 'Google')        if self.gp_addr.blank?
        self.fb_addr = info.try(:[], 'urls').try(:[], 'Facebook')      if self.fb_addr.blank?
        self.vk_addr = info.try(:[], 'urls').try(:[], 'Vkontakte')     if self.vk_addr.blank?
        self.tw_addr = info.try(:[], 'urls').try(:[], 'Twitter')       if self.tw_addr.blank?
        self.ok_addr = info.try(:[], 'urls').try(:[], 'Odnoklassniki') if self.ok_addr.blank?

        self.save
      end

      private

      # OAUTH helpers

      def oauth?; !oauth_data.blank?; end

      def oauth_params
        @oauth_params ||= (begin; JSON.parse oauth_data; rescue; nil; end)
      end

      def info
        @info ||= oauth_params.try(:[], 'info')
      end

      def extra
        @extra ||= oauth_params.try(:[], 'extra')
      end

      def raw_info
        @raw_info ||= oauth_params.try(:[], 'extra').try(:[], 'raw_info')
      end

      # base methods

      SocialNetworksLogin::Base.networks_list.each do |network_name|
        define_method "#{ network_name }_oauth?" do
          oauth_params['provider'] == network_name
        end
      end

      def create_credential
        uid          = oauth_params['uid']
        provider     = oauth_params['provider']
        _credentials = oauth_params.try(:[], 'credentials')

        create_credential_with_oauth(uid, provider, _credentials)
      end

      def define_login
        # generate by oauth data
        self.login = info.try(:[], 'nickname')        if self.login.blank?
        self.login = raw_info.try(:[], 'screen_name') if self.login.blank?

        # generate by username with number
        if self.login.blank? && self.username.present?
          login_counter = 0
          _login = self.username.to_slug_param

          while User.find_by_login(_login) do
            login_counter += 1
            _login = [ self.username.to_slug_param, login_counter ].join ?-
            _login = nil && break if login_counter == attempts_to_generate
          end

          self.login = _login
        end

        # generate by random value
        if self.login.blank?
          self.login = "user-#{ SecureRandom.hex[0..4] }"
        end
      end

      def define_email
        # generate by oauth data
        self.email = info.try(:[], 'email') if self.email.blank?

        # generate by login with number
        if self.email.blank? && self.login.present?
          email_counter = 0
          _email = [ self.login, default_email_domain ].join ?@

          while User.find_by_email(_email) do
            email_counter += 1
            _email = [ "#{ self.login }-#{ email_counter }", default_email_domain ].join ?@
            _email = nil && break if email_counter == attempts_to_generate
          end

          self.email = _email
        end

        # generate by random value
        if self.email.blank?
          self.email = "#{ SecureRandom.hex[0..6] }@#{ default_email_domain }"
        end
      end

      def define_password
        self.password = SecureRandom.hex[0..10]
      end

      def upload_oauth_avatar
        default_image = info.try(:[], 'image')
        gp_avatar, fb_avatar, tw_avatar = Array.new(3, default_image)

        vk_avatar = raw_info.try(:[], 'photo_200_orig')

        if facebook_oauth?
          json = JSON.parse(Net::HTTP.get(URI.parse(fb_avatar.gsub('&redirect=false', '') + '?type=large&redirect=false')))
          unless json['data']['is_silhouette']
            self.avatar = json['data']['url']
          end
        end

        if twitter_oauth?
          self.avatar = tw_avatar.gsub('_normal', '')
        end

        if vkontakte_oauth?
          self.avatar = vk_avatar
        end

        if google_oauth2_oauth?
          self.avatar = gp_avatar.gsub('s50', 's200').gsub('sz=50', 'sz=200')
        end

        if odnoklassniki_oauth?
          self.avatar = raw_info.try(:[], 'pic_2')
        end

        reset_oauth_data!
        save
      end

      def reset_oauth_data!
        self.oauth_data, @oauth_params = [nil, nil]
      end
    end
  end
end
