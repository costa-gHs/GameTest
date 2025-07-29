-- conf.lua - Configuração do LÖVE 2D para SLIME: Tempest Trials

function love.conf(t)
    -- Informações do jogo
    t.identity = "slime_tempest_trials"
    t.version = "11.4"
    t.console = false
    t.accelerometerjoystick = false
    t.externalstorage = false
    t.gammacorrect = false
    
    -- Configurações da janela
    t.window.title = "SLIME: Tempest Trials"
    t.window.icon = nil
    t.window.width = 1280
    t.window.height = 900
    t.window.borderless = false
    t.window.resizable = false
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.vsync = 1
    t.window.msaa = 0
    t.window.display = 1
    t.window.highdpi = false
    t.window.x = nil
    t.window.y = nil
    
    -- Módulos (desabilitar os não utilizados para performance)
    t.modules.audio = true
    t.modules.event = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = false -- Não usando Love2D physics
    t.modules.sound = true
    t.modules.system = true
    t.modules.timer = true
    t.modules.touch = false
    t.modules.video = false
    t.modules.window = true
    t.modules.thread = false
end 