class MouseHole::InstallerApp < MouseHole::App
  title 'Built-In Installer'
  description 'Senses MH2 user scripts and offers to install them.'
  version '2.0'
  accept Text

  + url("http://*.user.rb")

  def rewrite page
    page.headers['Location'] = "http://mh/doorway/install?url=#{page.location}"
    page.status = 303
    document.replace ""
  end
  
end
