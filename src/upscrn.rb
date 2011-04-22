$LOAD_PATH << File.dirname(__FILE__)
require 'loadpath'
require 'tray_app'
require 'screenshot'
require 'upscrn_client'
require 'url'

app = TrayApp.new("upscrn")
app.icon_filename = 'upscrn.ico'
app.item('Take Screenshot') do
  @image = Screenshot.capture(0, 0)
  @url = UpscrnClient.perform('post', 'screenshots', {:image => @image, })
  Url.show(@url)
end
app.item('Take Partial Screenshot') do
  @image = Screenshot.crop
end
app.item('Exit') {java.lang.System::exit(0)}
app.run

