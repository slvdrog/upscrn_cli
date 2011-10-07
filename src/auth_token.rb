class AuthToken
  include Java

  import java.util.Properties
  import java.io.FileInputStream
  import java.io.FileOutputStream
  import javax.swing.JButton
  import javax.swing.JFrame
  import javax.swing.JList
  import javax.swing.JTextField

  def initialize
    @config = Properties.new
    @projects = Properties.new
    begin
      @config.load(FileInputStream.new('config.properties'))
#      @projects.load(FileInputStream.new('projects.properties'))
    rescue
    end
#    self.get_projects
  end

  def get_token
    token = @config.get_property('token')
    return token
  end

  def set_token
    @frame = JFrame.new('Set Auth Token')
    @frame.set_bounds(500,500, 400, 100)
    @frame.set_layout(java.awt.FlowLayout.new);
    content = @frame.get_content_pane()
    @label = JTextField.new(15)
    button = JButton.new('Save Token')
    button.add_action_listener(self)
    content.add(@label)
    content.add(button)
    @frame.set_visible(true)
  end

  def get_projects
    token = @config.get_property('token')
    @project_list = UpscrnClient.perform('get', 'projects', token)
    p @project_list['projects']
    @project_list['projects'].each do |pr|
    	p '-----------------'
    	p pr
      @projects.set_property(pr['name'], pr['id'])
      @projects.store(FileOutputStream.new('projects.properties'), '')
      p pr['name'] + ' id:' + pr['id']
    end
    @projects.set_property('Public', 'public')
    @projects.store(FileOutputStream.new('projects.properties'), '')
  end

  def pick_project(image)
    @image = image
    project_enum = Array.new
    @projects.property_names().each do |pr|
      project_enum << pr
    end
    @frame = JFrame.new('Projects')
    @frame.set_bounds(500,500, 400, 100)
    @frame.set_layout(java.awt.FlowLayout.new)
    content = @frame.get_content_pane()
    @list = JList.new(project_enum.to_java)
    button = JButton.new('Pick Project')
    button.add_action_listener(self)
    content.add(@list)
    content.add(button)
    @frame.set_visible(true)
  end

  def actionPerformed(event)
    if event.source.get_label == 'Save Token'
      token = @label.get_text
      @config.set_property('token', token.to_s)
      @config.store(FileOutputStream.new('config.properties'), '')
      p 'Token saved'
      @frame.dispose
    else
      project = @list.get_selected_value()
      project = @projects.get_property(project)
      @frame.dispose
      p project
      token = @config.get_property('token')
      if project == 'public'
        @url = UpscrnClient.perform('post', 'screenshots', token, {:screenshot => {:image => @image}})
      else
        @url = UpscrnClient.perform("post", "projects/#{project}/screenshots", token,  {:screenshot => {:image => @image}})
      end
      show_url = Url.new
      show_url.show(@url)
      return project
    end
  end
end

class ProjectPicker

  def actionPerformed(event)
    p event.source.get_label
    p event.source.list.get_selected_value()
    project = event.source.list.get_selected_value()
    @frame.dispose
    p project
    return project
  end
end

