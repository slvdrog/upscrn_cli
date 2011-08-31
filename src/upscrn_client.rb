#$LOAD_PATH << 'lib/ruby/json/lib'
require 'lib/ruby/json/lib/json.rb'
require 'lib/ruby/rest_client/lib/restclient.rb'

class UpscrnClient
  class << self

    def perform(verb,action,auth_token, params={})
      action = [action, 'json'].join('.')
#      url = ['http://upscrn.com', action].join('/')
      url = ['http://127.0.0.1:3000', action].join('/')
      url = url + "?auth_token=#{auth_token}"
      p url
      JSON.parse(RestClient.send(verb,url,params).body)
    end
  end
end

