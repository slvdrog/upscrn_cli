$LOAD_PATH << File.dirname(__FILE__)
require 'loadpath'
require 'tray_app'
require 'screenshot'
require 'upscrn_client'
require 'url'
require 'auth_token'

import javax.swing.JFrame
import javax.swing.JTextField

auth_token = AuthToken.new
app = TrayApp.new("upscrn")
app.icon_filename = 'upscrn.ico'
app.item('Take Screenshot') do
  show_url = Url.new
  @image = Screenshot.capture(0, 0)
  token = auth_token.get_token
  @url = UpscrnClient.perform('post', 'screenshots', {:image => @image, :auth_token => token})
  show_url.show(@url)
end
app.item('Take Partial Screenshot') do
  @image = Screenshot.crop
end
app.item('Set Auth Token') do
  auth_token.set_token
end
app.item('Exit') {java.lang.System::exit(0)}
app.run

