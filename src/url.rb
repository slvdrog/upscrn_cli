class Url
  include Java

  import java.awt.Toolkit
  import javax.swing.JButton
  import javax.swing.JFrame
  import javax.swing.JTextField
  java.awt.datatransfer.Clipboard

  def show(url)
    frame = JFrame.new("Screenshot URL")
    frame.set_bounds(500,500, 400, 100)
    frame.set_layout(java.awt.FlowLayout.new);
    content = frame.get_content_pane()
#    button = JButton.new('Copy to Clipboard')
#    button.add_action_listener(self)
    @label = JTextField.new(url['url'], url['url'].length)
    @label.set_editable(false)
    content.add(@label)
#    content.add(button)
    frame.set_visible(true)
  end

  def actionPerformed(event)
    copy_to_clip = @label.get_text
    toolkit   = Toolkit.get_default_toolkit
    clipboard = Clipboard.new('clipboard')
    clipboard = toolkit.get_system_clipboard
    clipboard.set_contents(copy_to_clip, copy_to_clip)
  end

end

