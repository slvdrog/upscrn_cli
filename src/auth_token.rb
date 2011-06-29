class AuthToken
  include Java

  import java.util.Properties
  import java.io.FileInputStream
  import java.io.FileOutputStream
  import javax.swing.JButton
  import javax.swing.JFrame
  import javax.swing.JTextField

  def initialize
    @config = Properties.new
    begin
      @config.load(FileInputStream.new('config.properties'))
    rescue
    end
  end

  def get_token
    token = @config.get_property('token')
    return token
  end

  def set_token
    frame = JFrame.new('Set Auth Token')
    frame.set_bounds(500,500, 400, 100)
    frame.set_layout(java.awt.FlowLayout.new);
    content = frame.get_content_pane()
    @label = JTextField.new(15)
    button = JButton.new('Save Token')
    button.add_action_listener(self)
    content.add(@label)
    content.add(button)
    frame.set_visible(true)
  end


  def actionPerformed(event)
    token = @label.get_text
    @config.set_property('token', token.to_s)
    @config.store(FileOutputStream.new('config.properties'), '')
  end

end

