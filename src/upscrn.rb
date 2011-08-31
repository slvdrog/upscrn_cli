$LOAD_PATH << File.dirname(__FILE__)
require 'loadpath'
require 'tray_app'
require 'screenshot'
require 'upscrn_client'
require 'url'
require 'auth_token'

import javax.swing.JFrame
import javax.swing.JTextField

config = AuthToken.new
app = TrayApp.new("upscrn")
app.icon_filename = 'upscrn.ico'
app.item('Take Screenshot') do
  @image = Screenshot.capture(0, 0)
  project = config.pick_project(@image)
end
app.item('Take Partial Screenshot') do
  Screenshot.crop
end
app.item('Set Auth Token') do
  config.set_token
end
app.item('Get Projects List') do
  config.get_projects
end
app.item('Exit') {java.lang.System::exit(0)}
app.run

