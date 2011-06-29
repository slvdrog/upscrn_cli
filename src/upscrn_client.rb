#$LOAD_PATH << 'lib/ruby/json/lib'
require 'lib/ruby/json/lib/json.rb'
require 'lib/ruby/rest_client/lib/restclient.rb'

class UpscrnClient
  class << self

    def perform(verb,action,params={})
      action = [action, 'json'].join('.')
      url = ['http://www.upscrn.com', action].join('/')
#      url = ['http://127.0.0.1:3000', action].join('/')
      JSON.parse(RestClient.send(verb,url,params).body)
    end
  end
end

