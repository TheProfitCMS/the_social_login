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
      before_validation :fakes_for_oauth,    on: :create, if: ->{ oauth? }
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
        'open-cook.ru'
      end

      # do something common here
      def set_params_common_oauth
        info = oauth_info
        self.username = info.try(:[], 'name')
      end

      # do something special here
      def set_params_from_gp_oauth
        self.email   = oauth_info.try(:[], 'email')
        self.gp_addr = oauth_info.try(:[], 'urls').try(:[], 'Google')
      end

      def set_params_from_fb_oauth
        self.email = oauth_info.try(:[], 'email')
        self.fb_addr = oauth_info.try(:[], 'urls').try(:[], 'Facebook')
      end

      def set_params_from_vk_oauth
        info = oauth_info
        self.login = info.try(:[], 'nickname')
        self.vk_addr = oauth_info.try(:[], 'urls').try(:[], 'Vkontakte')
      end

      def set_params_from_tw_oauth
        info = oauth_info
        self.login = info.try(:[], 'nickname')
        self.tw_addr = oauth_info.try(:[], 'urls').try(:[], 'Twitter')
      end

      def set_params_from_ok_oauth
        self.ok_addr = oauth_info.try(:[], 'urls').try(:[], 'Odnoklassniki')
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

        self.gp_addr = info.try(:[], 'urls').try(:[], 'Google')        if gp_addr.blank?
        self.fb_addr = info.try(:[], 'urls').try(:[], 'Facebook')      if fb_addr.blank?
        self.vk_addr = info.try(:[], 'urls').try(:[], 'Vkontakte')     if vk_addr.blank?
        self.tw_addr = info.try(:[], 'urls').try(:[], 'Twitter')       if tw_addr.blank?
        self.ok_addr = info.try(:[], 'urls').try(:[], 'Odnoklassniki') if ok_addr.blank?

        self.save
      end

      private

      def oauth_info
        oauth_params.try(:[], 'info')
      end

      def oauth?; !oauth_data.blank?; end

      def oauth_params
        @oauth_params ||= (begin; JSON.parse oauth_data; rescue; nil; end)
      end

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

      def fakes_for_oauth
        _email = "#{ SecureRandom.hex[0..6] }@#{ default_email_domain }"
        _login = "user-#{ SecureRandom.hex[0..4] }"

        self.email    = self.email.blank? ? _email : self.email
        self.login    = self.login.blank? ? _login : self.login
        self.password = SecureRandom.hex[0..10]
      end

      def upload_oauth_avatar
        info     = oauth_info
        extra    = oauth_params.try(:[], 'extra')
        raw_info = extra.try(:[], 'raw_info')

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
