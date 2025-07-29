-- app.lua - Core Application Manager
-- Gerencia estados de jogo, loop principal e inicialização

local App = {}
local EventBus = require("src.core.eventbus")
local SaveManager = require("src.core.save")

-- Estados do jogo
local GameStates = {
    MAIN_MENU = "main_menu",
    PLAYING = "playing", 
    PAUSED = "paused",
    INVENTORY = "inventory",
    ANALYSIS = "analysis",
    CITY = "city",
    GAME_OVER = "game_over"
}

function App:new()
    local app = {}
    setmetatable(app, { __index = self })
    
    app.state = GameStates.MAIN_MENU
    app.previousState = nil
    app.stateStack = {}
    app.deltaTime = 0
    app.totalTime = 0
    
    -- Módulos do jogo
    app.world = nil
    app.slime = nil
    app.sage = nil
    app.combat = nil
    app.ui = nil
    app.spriteGenerator = nil
    
    -- Configuração global
    app.config = {
        seed = os.time(),
        difficulty = "normal",
        debug = false,
        
        meta = {
            techUnlocked = {},
            cityLevel = 0,
            runsCompleted = 0,
            totalEssence = 0
        },
        
        predation = {
            baseRange = 32,
            channelTime = 1.0,
            stomachCapacity = 8,
            analysisRate = 1.0,
            alertPenalty = 0.5
        },
        
        sage = {
            level = 1, -- 1: Sábio | 2: Sábio+ | 3: Raphael-like
            hints = true,
            autoAnalysis = false
        },
        
        biomes = {"floresta_temperada", "pantano_tempestuoso", "cavernas_de_cristal"}
    }
    
    return app
end

function App:initialize()
    -- Carregar save data
    local saveData = SaveManager:load()
    if saveData then
        self.config.meta = saveData.meta or self.config.meta
        self.config.sage = saveData.sage or self.config.sage
    end
    
    -- Inicializar módulos
    self:loadModules()
    
    -- Setup Love2D callbacks
    self:setupCallbacks()
    
    -- Eventos iniciais
    EventBus:emit("app:initialized", self.config)
    
    print("SLIME: Tempest Trials - Inicializado")
    print("Seed: " .. self.config.seed)
end

function App:loadModules()
    -- Core systems
    local RNG = require("src.core.rng")
    RNG:setSeed(self.config.seed)
    
    -- Sprite generator (integrar o existente)
    self.spriteGenerator = require("main") -- Usar o gerador existente
    
    -- Gameplay systems
    local SlimeController = require("src.gameplay.slime")
    local SageAdvisor = require("src.gameplay.sage")
    local WorldGenerator = require("src.world.gen")
    local CombatSystem = require("src.combat.combat")
    local UIManager = require("src.render.ui")
    
    self.slime = SlimeController:new(self.config)
    self.sage = SageAdvisor:new(self.config.sage)
    self.world = WorldGenerator:new(self.config)
    self.combat = CombatSystem:new()
    self.ui = UIManager:new(self.config)
end

function App:setState(newState)
    if self.state ~= newState then
        self.previousState = self.state
        self.state = newState
        EventBus:emit("state:changed", {
            from = self.previousState,
            to = newState
        })
    end
end

function App:pushState(newState)
    table.insert(self.stateStack, self.state)
    self:setState(newState)
end

function App:popState()
    if #self.stateStack > 0 then
        local previousState = table.remove(self.stateStack)
        self:setState(previousState)
        return true
    end
    return false
end

function App:update(dt)
    self.deltaTime = dt
    self.totalTime = self.totalTime + dt
    
    -- Update baseado no estado
    if self.state == GameStates.PLAYING then
        if self.world then self.world:update(dt) end
        if self.slime then self.slime:update(dt) end
        if self.combat then self.combat:update(dt) end
        if self.sage then self.sage:update(dt) end
    elseif self.state == GameStates.ANALYSIS then
        if self.slime then self.slime:updateAnalysis(dt) end
        if self.sage then self.sage:update(dt) end
    end
    
    -- UI sempre atualiza
    if self.ui then self.ui:update(dt) end
    
    -- Processar eventos
    EventBus:update(dt)
end

function App:draw()
    if self.state == GameStates.PLAYING then
        if self.world then self.world:draw() end
        if self.slime then self.slime:draw() end
        if self.combat then self.combat:draw() end
    end
    
    -- UI overlay
    if self.ui then self.ui:draw(self.state) end
    
    -- Debug info
    if self.config.debug then
        self:drawDebugInfo()
    end
end

function App:drawDebugInfo()
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
    love.graphics.print("State: " .. self.state, 10, 30)
    love.graphics.print("Seed: " .. self.config.seed, 10, 50)
    if self.slime then
        love.graphics.print("Slime HP: " .. self.slime.health, 10, 70)
        love.graphics.print("Essence: " .. self.slime.essence, 10, 90)
    end
end

function App:setupCallbacks()
    -- Mapear callbacks do Love2D para os sistemas apropriados
    function love.keypressed(key)
        if key == "escape" then
            if self.state == GameStates.PLAYING then
                self:setState(GameStates.PAUSED)
            elseif self.state == GameStates.PAUSED then
                self:setState(GameStates.PLAYING)
            end
        elseif key == "f1" then
            self.config.debug = not self.config.debug
        elseif key == "i" and self.state == GameStates.PLAYING then
            self:pushState(GameStates.INVENTORY)
        elseif key == "a" and self.state == GameStates.PLAYING then
            self:pushState(GameStates.ANALYSIS)
        end
        
        -- Propagar para sistemas
        if self.ui then self.ui:keypressed(key) end
        if self.slime and self.state == GameStates.PLAYING then 
            self.slime:keypressed(key) 
        end
    end
    
    function love.mousepressed(x, y, button)
        if self.ui then self.ui:mousepressed(x, y, button) end
        if self.slime and self.state == GameStates.PLAYING then
            self.slime:mousepressed(x, y, button)
        end
    end
end

function App:startNewRun()
    -- Gerar novo mundo
    self.config.seed = os.time() + math.random(1000)
    local RNG = require("src.core.rng")
    RNG:setSeed(self.config.seed)
    
    -- Reset do slime
    if self.slime then
        self.slime:reset()
    end
    
    -- Gerar mundo
    if self.world then
        self.world:generate()
    end
    
    self:setState(GameStates.PLAYING)
    EventBus:emit("run:started", {seed = self.config.seed})
end

function App:endRun(victory)
    -- Calcular recompensas de metaprogressão
    local essence = self.slime and self.slime.essence or 0
    local persistentEssence = math.floor(essence * 0.1) -- 10% persiste
    
    self.config.meta.totalEssence = self.config.meta.totalEssence + persistentEssence
    if victory then
        self.config.meta.runsCompleted = self.config.meta.runsCompleted + 1
    end
    
    -- Salvar progresso
    SaveManager:save(self.config)
    
    self:setState(GameStates.GAME_OVER)
    EventBus:emit("run:ended", {
        victory = victory,
        essence = essence,
        persistentEssence = persistentEssence
    })
end

-- Singleton instance
local appInstance = nil

function App.getInstance()
    if not appInstance then
        appInstance = App:new()
    end
    return appInstance
end

return App 