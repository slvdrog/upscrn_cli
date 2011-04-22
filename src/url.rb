class Url
  include Java

  import javax.swing.JFrame
  import javax.swing.JTextField

  def self.show(url)
    frame = JFrame.new("Screenshot URL")
    frame.set_bounds(500,500, 400, 100)
    content = frame.getContentPane()
    label = JTextField.new(url['url'])
    label.set_editable(false)
    content.add(label)
    frame.set_visible(true)

  end
end

