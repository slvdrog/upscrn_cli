#$LOAD_PATH << 'lib/ruby/json/lib'
require 'json'
require 'rest_client'

class UpscrnClient
  class << self

    def perform(verb,action,params={})
      action = [action, 'json'].join('.')
      url = ['http://upscrn.heroku.com', action].join('/')
      JSON.parse(RestClient.send(verb,url,params).body)
    end
  end
end

