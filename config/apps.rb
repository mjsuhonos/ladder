Padrino.configure_apps do
  enable :sessions
  set :session_secret, '5f64872da40cede6ba8f282a61da62f644ec018febad73ca096f5b271bafd76d'
end

# Mounts the core application for this project
Padrino.mount("Ladder").to('/')
