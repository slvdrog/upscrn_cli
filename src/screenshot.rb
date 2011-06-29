class Screenshot
  include Java

  import java.awt.event
  import java.awt.Rectangle
  import java.awt.Robot
  import java.awt.Toolkit
  import java.awt.image.BufferedImage
  import javax.imageio.ImageIO
  import javax.swing.JFrame
  import javax.swing.JPanel

  def self.capture(x, y, dim = nil, filename = 'fullscrn.jpg')
    robot = Robot.new
    if dim == nil
      toolkit   = Toolkit.get_default_toolkit
      dim       = toolkit.get_screen_size
    end
    rectangle = Rectangle.new(x, y, dim.get_width, dim.get_height)
    image     = robot.create_screen_capture(rectangle)
    file  = java::io::File.new(filename)
    ImageIO::write(image, "jpg", file)
    if filename == 'fullscrn.jpg'
      return File.open filename, 'r'
    else
      return dim
    end
   end

  def self.crop
    dim = Screenshot.capture(0, 0, nil, 'partscrn.jpg')

    frame = JFrame.new()
    frame.set_bounds(0, 0, dim.get_width, dim.get_height)
    frame.setUndecorated(true)
    listener = Listener.new
    panel = CropPanel.new
    panel.add_mouse_listener(listener)
    panel.add_mouse_motion_listener(listener)
    frame.set_content_pane(panel)
    frame.set_visible(true)
  end

end

class CropPanel < javax.swing.JPanel

  import java.awt.BasicStroke
  import java.awt.Color
	import java.awt.Graphics
  import java.lang.Math

  def new_size(beginX, beginY, width, height)
    @dragMode = true
    @beginX = beginX
    @beginY = beginY
    @width = width
    @height = height
  end

  def paintComponent(g)
    super(g)
    file  = java::io::File.new('partscrn.jpg')
    @image = javax::imageio::ImageIO::read(file)
    g.draw_image(@image, 0, 0, nil)
    if @dragMode == true
      g.set_color(Color.red)
      g.set_stroke(BasicStroke.new(7));
      g.draw_rect(@beginX, @beginY, @width, @height)
    else
      g.draw_string("Make your selection by dragging the mouse", 10, 25)
    end
  end

  def crop(filename)
    auth_token = AuthToken.new
    token = auth_token.get_token
    p @token
    cropped = @image.get_subimage(@beginX, @beginY, @width, @height)
    file  = java::io::File.new(filename)
    javax::imageio::ImageIO::write(cropped, "jpg", file)
    cropped = File.open filename, 'r'

    show_url = Url.new
    @url = UpscrnClient.perform('post', 'screenshots', {:image => cropped, :auth_token => token})
    show_url.show(@url)
#    return File.open filename, 'r'
  end

end

class Listener
	  include java.awt.event.MouseListener
	  include java.awt.event.MouseMotionListener

    import java.lang.Math
	  import java.awt.Dimension
	  import java.awt.event.MouseEvent
	  import java.awt.event.MouseListener
	  import java.awt.event.MouseMotionListener

    def mouseDragged(event)
      @currentX = event.getX()
      @currentY = event.getY()
      beginX = Math.min(@startX, @currentX)
      beginY = Math.min(@startY, @currentY)
      width  = Math.abs(@currentX - @startX)
      height = Math.abs(@currentY - @startY)
      event.source.new_size(beginX, beginY, width, height)
      event.source.repaint()
    end

    def mousePressed(event)
      @startX = event.getX()
      @startY = event.getY()
    end

    def mouseReleased(event)
      response = javax::swing::JOptionPane.showConfirmDialog(nil, "Crop the image to selected size?");
      if response == 0
        event.source.get_top_level_ancestor.set_visible(false)
        event.source.crop('partscrn.jpg')
      else
        if response == 2
          event.source.get_top_level_ancestor.set_visible(false)
        end
      end

    end

    def mouseClicked(event)
    end
    def mouseMoved(event)
    end
    def mouseExited(event)
    end
    def mouseEntered(event)
    end
end

