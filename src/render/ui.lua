-- ui.lua - Sistema de UI Visual Completo
-- HUD, árvore de evolução, janelas de análise, inventário

local UIManager = {}
local EventBus = require("src.core.eventbus")

-- Estados da UI
local UIState = {
    GAME_HUD = "game_hud",
    ANALYSIS_WINDOW = "analysis_window", 
    SKILL_TREE = "skill_tree",
    INVENTORY = "inventory",
    PAUSE_MENU = "pause_menu"
}

-- Cores da UI
local UIColors = {
    background = {0.05, 0.05, 0.08, 0.9},
    panel = {0.1, 0.1, 0.12, 0.95},
    panelLight = {0.15, 0.15, 0.18, 0.9},
    accent = {0.3, 0.7, 0.9, 1},
    accentDark = {0.2, 0.5, 0.7, 1},
    text = {0.9, 0.9, 0.9, 1},
    textDim = {0.6, 0.6, 0.6, 1},
    success = {0.3, 0.8, 0.3, 1},
    warning = {0.9, 0.7, 0.2, 1},
    error = {0.9, 0.3, 0.3, 1},
    health = {0.8, 0.2, 0.2, 1},
    essence = {0.2, 0.6, 0.9, 1},
    mana = {0.5, 0.3, 0.8, 1}
}

function UIManager:new(config)
    local ui = {}
    setmetatable(ui, { __index = self })
    
    ui.config = config
    ui.currentState = UIState.GAME_HUD
    ui.windows = {}
    ui.animations = {}
    ui.notifications = {}
    
    -- Configurar fontes
    ui.fonts = {
        small = love.graphics.newFont(10),
        normal = love.graphics.newFont(12),
        medium = love.graphics.newFont(14),
        large = love.graphics.newFont(18),
        title = love.graphics.newFont(24)
    }
    
    -- Configurar janelas
    ui:initializeWindows()
    
    -- Configurar eventos
    ui:setupEventListeners()
    
    return ui
end

function UIManager:initializeWindows()
    local screenW, screenH = love.graphics.getWidth(), love.graphics.getHeight()
    
    self.windows = {
        hud = {
            x = 0, y = 0, width = screenW, height = screenH,
            visible = true
        },
        
        analysis = {
            x = screenW * 0.2, y = screenH * 0.15,
            width = screenW * 0.6, height = screenH * 0.7,
            visible = false,
            title = "Análise - Estômago Espacial"
        },
        
        skillTree = {
            x = screenW * 0.1, y = screenH * 0.1,
            width = screenW * 0.8, height = screenH * 0.8,
            visible = false,
            title = "Árvore de Evolução"
        },
        
        inventory = {
            x = screenW * 0.25, y = screenH * 0.2,
            width = screenW * 0.5, height = screenH * 0.6,
            visible = false,
            title = "Inventário & Habilidades"
        }
    }
end

function UIManager:setupEventListeners()
    -- Notificações do sistema
    EventBus:on("trait:discovered", function(data)
        self:addNotification("Novo traço: " .. data.trait.name, UIColors.success, 3.0)
    end)
    
    EventBus:on("skill:evolved", function(data)
        self:addNotification("EVOLUÇÃO: " .. data.newSkill.name, UIColors.warning, 4.0)
    end)
    
    EventBus:on("predation:completed", function(data)
        self:addNotification("Predação completa", UIColors.accent, 2.0)
    end)
    
    EventBus:on("sage:advice", function(data)
        self:addNotification("[Sábio] " .. data.advice.message, UIColors.mana, 5.0)
    end)
    
    EventBus:on("combat:damage_applied", function(data)
        if data.fatal then
            self:addNotification("Inimigo derrotado!", UIColors.success, 2.0)
        end
    end)
end

function UIManager:update(dt)
    -- Atualizar animações
    for i = #self.animations, 1, -1 do
        local anim = self.animations[i]
        anim.timer = anim.timer + dt
        
        if anim.timer >= anim.duration then
            table.remove(self.animations, i)
        end
    end
    
    -- Atualizar notificações
    for i = #self.notifications, 1, -1 do
        local notif = self.notifications[i]
        notif.timer = notif.timer + dt
        
        if notif.timer >= notif.duration then
            table.remove(self.notifications, i)
        end
    end
end

function UIManager:draw(gameState)
    -- Desenhar HUD principal
    if self.currentState == UIState.GAME_HUD or gameState == "playing" then
        self:drawHUD()
    end
    
    -- Desenhar janelas ativas
    if self.windows.analysis.visible then
        self:drawAnalysisWindow()
    end
    
    if self.windows.skillTree.visible then
        self:drawSkillTree()
    end
    
    if self.windows.inventory.visible then
        self:drawInventory()
    end
    
    -- Desenhar notificações
    self:drawNotifications()
    
    -- Desenhar cursor customizado se necessário
    self:drawCursor()
end

function UIManager:drawHUD()
    local app = require("src.core.app").getInstance()
    if not app or not app.slime then return end
    
    local slimeStats = app.slime:getStats()
    
    -- Painel de status principal (superior esquerdo)
    self:drawStatusPanel(slimeStats)
    
    -- Barra de predação (centro inferior)
    self:drawPredationBar(slimeStats)
    
    -- Conselhos do Sábio (superior direito)
    self:drawSageAdvice()
    
    -- Minimapa (inferior direito)
    self:drawMinimap()
    
    -- Controles de ação (inferior centro)
    self:drawActionControls()
end

function UIManager:drawStatusPanel(stats)
    local panelW, panelH = 250, 120
    local x, y = 20, 20
    
    -- Fundo do painel
    love.graphics.setColor(UIColors.panel)
    self:drawRoundedRect(x, y, panelW, panelH, 8)
    
    -- Borda
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(2)
    self:drawRoundedRectOutline(x, y, panelW, panelH, 8)
    
    -- Vida
    love.graphics.setFont(self.fonts.normal)
    love.graphics.setColor(UIColors.text)
    love.graphics.print("HP", x + 10, y + 10)
    
    local healthPercent = stats.health / stats.maxHealth
    self:drawProgressBar(x + 40, y + 10, 180, 16, healthPercent, UIColors.health)
    love.graphics.setColor(UIColors.text)
    love.graphics.print(stats.health .. "/" .. stats.maxHealth, x + 180, y + 28)
    
    -- Essência
    love.graphics.print("Essência", x + 10, y + 45)
    love.graphics.setColor(UIColors.essence)
    love.graphics.print(stats.essence, x + 80, y + 45)
    
    -- Estado atual
    love.graphics.setColor(UIColors.textDim)
    love.graphics.setFont(self.fonts.small)
    love.graphics.print("Estado: " .. stats.state, x + 10, y + 65)
    
    -- Forma atual
    if stats.currentForm ~= "base" then
        love.graphics.setColor(UIColors.warning)
        love.graphics.print("Forma: " .. stats.currentForm, x + 10, y + 80)
        
        -- Barra de tempo da forma
        if stats.mimicryTimer > 0 then
            local formPercent = stats.mimicryTimer / 30 -- Assumindo 30s padrão
            self:drawProgressBar(x + 80, y + 80, 120, 12, 1 - formPercent, UIColors.warning)
        end
    end
    
    -- Contador de traços/habilidades
    love.graphics.setColor(UIColors.accent)
    love.graphics.print("Traços: " .. stats.traitCount, x + 10, y + 95)
    love.graphics.print("Formas: " .. stats.formCount, x + 80, y + 95)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawPredationBar(stats)
    local progress = stats.predation and stats.predation.state == "channeling" and 
                    (stats.predation.channelTime or 0) / 2.0 or 0
    
    if progress > 0 then
        local barW, barH = 300, 20
        local x = (love.graphics.getWidth() - barW) / 2
        local y = love.graphics.getHeight() - 100
        
        -- Fundo
        love.graphics.setColor(UIColors.background)
        self:drawRoundedRect(x - 5, y - 5, barW + 10, barH + 10, 5)
        
        -- Barra de progresso
        self:drawProgressBar(x, y, barW, barH, progress, UIColors.accent)
        
        -- Texto
        love.graphics.setColor(UIColors.text)
        love.graphics.setFont(self.fonts.medium)
        local text = "Predação em andamento..."
        local textW = self.fonts.medium:getWidth(text)
        love.graphics.print(text, x + (barW - textW) / 2, y - 25)
    end
end

function UIManager:drawSageAdvice()
    local app = require("src.core.app").getInstance()
    if not app or not app.slime then return end
    
    local advice = app.slime:getCurrentAdvice()
    if not advice then return end
    
    local panelW, panelH = 350, 80
    local x = love.graphics.getWidth() - panelW - 20
    local y = 20
    
    -- Fundo do painel
    love.graphics.setColor(UIColors.panel)
    self:drawRoundedRect(x, y, panelW, panelH, 8)
    
    -- Borda colorida baseada no tipo
    local borderColor = UIColors.mana
    if advice.type == "warning" then borderColor = UIColors.warning
    elseif advice.type == "combat" then borderColor = UIColors.error end
    
    love.graphics.setColor(borderColor)
    love.graphics.setLineWidth(2)
    self:drawRoundedRectOutline(x, y, panelW, panelH, 8)
    
    -- Ícone do Sábio
    love.graphics.setColor(UIColors.accent)
    love.graphics.circle("fill", x + 25, y + 25, 15)
    love.graphics.setColor(UIColors.background)
    love.graphics.setFont(self.fonts.medium)
    love.graphics.print("S", x + 20, y + 15)
    
    -- Texto do conselho
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.small)
    local wrapped = self:wrapText(advice.message, panelW - 60, self.fonts.small)
    love.graphics.print(wrapped, x + 50, y + 10)
    
    -- Botão para dispensar
    love.graphics.setColor(UIColors.textDim)
    love.graphics.print("[Tab] Dispensar", x + 10, y + panelH - 15)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawMinimap()
    local app = require("src.core.app").getInstance()
    if not app or not app.world then return end
    
    local mapSize = 150
    local x = love.graphics.getWidth() - mapSize - 20
    local y = love.graphics.getHeight() - mapSize - 20
    
    -- Fundo do minimapa
    love.graphics.setColor(UIColors.background)
    self:drawRoundedRect(x, y, mapSize, mapSize, 8)
    
    -- Borda
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(1)
    self:drawRoundedRectOutline(x, y, mapSize, mapSize, 8)
    
    -- Desenhar mundo simplificado
    if app.world and app.world.draw then
        -- Salvar estado de transformação
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(mapSize / 512, mapSize / 512) -- Escala do mundo
        
        -- Desenhar mapa do mundo em miniatura
        app.world:draw()
        
        love.graphics.pop()
    end
    
    -- Título
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.small)
    love.graphics.print("Mapa", x + 5, y - 15)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawActionControls()
    local controls = {
        {key = "Espaço", action = "Predação"},
        {key = "A", action = "Analisar"},
        {key = "Q", action = "Forma"},
        {key = "I", action = "Inventário"},
        {key = "T", action = "Habilidades"}
    }
    
    local totalW = #controls * 80
    local startX = (love.graphics.getWidth() - totalW) / 2
    local y = love.graphics.getHeight() - 50
    
    for i, control in ipairs(controls) do
        local x = startX + (i - 1) * 80
        
        -- Fundo da tecla
        love.graphics.setColor(UIColors.panelLight)
        self:drawRoundedRect(x, y, 70, 30, 4)
        
        -- Borda
        love.graphics.setColor(UIColors.accent)
        love.graphics.setLineWidth(1)
        self:drawRoundedRectOutline(x, y, 70, 30, 4)
        
        -- Texto da tecla
        love.graphics.setColor(UIColors.text)
        love.graphics.setFont(self.fonts.small)
        local keyW = self.fonts.small:getWidth(control.key)
        love.graphics.print(control.key, x + (70 - keyW) / 2, y + 5)
        
        -- Ação
        love.graphics.setColor(UIColors.textDim)
        local actionW = self.fonts.small:getWidth(control.action)
        love.graphics.print(control.action, x + (70 - actionW) / 2, y + 18)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawAnalysisWindow()
    local window = self.windows.analysis
    if not window.visible then return end
    
    -- Fundo da janela
    love.graphics.setColor(UIColors.background)
    self:drawRoundedRect(window.x, window.y, window.width, window.height, 12)
    
    -- Borda
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(3)
    self:drawRoundedRectOutline(window.x, window.y, window.width, window.height, 12)
    
    -- Título
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.title)
    love.graphics.print(window.title, window.x + 20, window.y + 15)
    
    -- Botão fechar
    local closeX = window.x + window.width - 40
    local closeY = window.y + 15
    love.graphics.setColor(UIColors.error)
    love.graphics.circle("fill", closeX, closeY + 10, 12)
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.medium)
    love.graphics.print("X", closeX - 5, closeY + 2)
    
    -- Conteúdo da análise
    local contentY = window.y + 60
    self:drawAnalysisContent(window.x + 20, contentY, window.width - 40, window.height - 80)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawAnalysisContent(x, y, w, h)
    local app = require("src.core.app").getInstance()
    if not app or not app.slime then return end
    
    local analysisStats = app.slime.analysis:getStats()
    
    -- Estado da análise
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.medium)
    love.graphics.print("Estado: " .. (analysisStats.state or "idle"), x, y)
    
    if analysisStats.state == "analyzing" then
        local progress, completed, total = app.slime.analysis:getAnalysisProgress()
        love.graphics.print("Progresso: " .. completed .. "/" .. total, x, y + 25)
        
        -- Barra de progresso
        if total > 0 then
            self:drawProgressBar(x, y + 50, w - 20, 20, completed / total, UIColors.accent)
        end
    end
    
    -- Descobertas recentes
    love.graphics.setFont(self.fonts.medium)
    love.graphics.print("Descobertas Recentes:", x, y + 80)
    
    local discoveries = app.slime.analysis:getRecentDiscoveries(5)
    for i, discovery in ipairs(discoveries) do
        local itemY = y + 110 + (i - 1) * 60
        
        -- Fundo do item
        love.graphics.setColor(UIColors.panelLight)
        self:drawRoundedRect(x, itemY, w - 20, 50, 6)
        
        -- Info do item
        love.graphics.setColor(UIColors.text)
        love.graphics.setFont(self.fonts.normal)
        love.graphics.print("Item: " .. (discovery.item.type or "unknown"), x + 10, itemY + 5)
        love.graphics.print("Traços: " .. #discovery.discoveries.traits, x + 10, itemY + 25)
        love.graphics.print("Essência: " .. discovery.discoveries.essence, x + 200, itemY + 5)
        love.graphics.print("Formas: " .. #discovery.discoveries.forms, x + 200, itemY + 25)
    end
end

function UIManager:drawSkillTree()
    local window = self.windows.skillTree
    if not window.visible then return end
    
    -- Fundo da janela
    love.graphics.setColor(UIColors.background)
    self:drawRoundedRect(window.x, window.y, window.width, window.height, 12)
    
    -- Borda
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(3)
    self:drawRoundedRectOutline(window.x, window.y, window.width, window.height, 12)
    
    -- Título
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.title)
    love.graphics.print(window.title, window.x + 20, window.y + 15)
    
    -- Conteúdo da árvore de habilidades
    local contentY = window.y + 60
    self:drawSkillTreeContent(window.x + 20, contentY, window.width - 40, window.height - 80)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawSkillTreeContent(x, y, w, h)
    local app = require("src.core.app").getInstance()
    if not app or not app.slime then return end
    
    local slimeStats = app.slime:getStats()
    
    -- Categorias de traços
    local categories = {"combat", "movement", "utility", "survival", "magic"}
    local colWidth = w / #categories
    
    for i, category in ipairs(categories) do
        local colX = x + (i - 1) * colWidth
        
        -- Título da categoria
        love.graphics.setColor(UIColors.accent)
        love.graphics.setFont(self.fonts.medium)
        love.graphics.print(category:upper(), colX + 10, y)
        
        -- Placeholder para traços da categoria
        love.graphics.setColor(UIColors.panelLight)
        self:drawRoundedRect(colX + 5, y + 30, colWidth - 10, h - 40, 6)
        
        -- Lista simplificada de traços
        for j = 1, 5 do
            local slotY = y + 40 + (j - 1) * 40
            love.graphics.setColor(UIColors.panel)
            self:drawRoundedRect(colX + 10, slotY, colWidth - 20, 30, 4)
            
            love.graphics.setColor(UIColors.textDim)
            love.graphics.setFont(self.fonts.small)
            love.graphics.print("Slot " .. j, colX + 15, slotY + 8)
        end
    end
end

function UIManager:drawInventory()
    local window = self.windows.inventory
    if not window.visible then return end
    
    -- Fundo da janela
    love.graphics.setColor(UIColors.background)
    self:drawRoundedRect(window.x, window.y, window.width, window.height, 12)
    
    -- Borda
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(3)
    self:drawRoundedRectOutline(window.x, window.y, window.width, window.height, 12)
    
    -- Título
    love.graphics.setColor(UIColors.text)
    love.graphics.setFont(self.fonts.title)
    love.graphics.print(window.title, window.x + 20, window.y + 15)
    
    -- Abas
    local tabs = {"Traços", "Formas", "Habilidades"}
    local tabW = 100
    for i, tab in ipairs(tabs) do
        local tabX = window.x + 20 + (i - 1) * (tabW + 5)
        local tabY = window.y + 45
        
        love.graphics.setColor(i == 1 and UIColors.accent or UIColors.panelLight)
        self:drawRoundedRect(tabX, tabY, tabW, 25, 4)
        
        love.graphics.setColor(UIColors.text)
        love.graphics.setFont(self.fonts.normal)
        local textW = self.fonts.normal:getWidth(tab)
        love.graphics.print(tab, tabX + (tabW - textW) / 2, tabY + 5)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function UIManager:drawNotifications()
    local startY = 100
    
    for i, notif in ipairs(self.notifications) do
        local y = startY + (i - 1) * 35
        local alpha = math.max(0, 1 - (notif.timer / notif.duration))
        
        -- Fundo da notificação
        local bgColor = {notif.color[1], notif.color[2], notif.color[3], alpha * 0.8}
        love.graphics.setColor(bgColor)
        
        local textW = self.fonts.normal:getWidth(notif.text)
        local x = love.graphics.getWidth() - textW - 30
        self:drawRoundedRect(x - 10, y - 5, textW + 20, 25, 4)
        
        -- Texto
        local textColor = {1, 1, 1, alpha}
        love.graphics.setColor(textColor)
        love.graphics.setFont(self.fonts.normal)
        love.graphics.print(notif.text, x, y)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

function UIManager:drawCursor()
    -- Cursor customizado se necessário
    local x, y = love.mouse.getPosition()
    
    -- Simples crosshair
    love.graphics.setColor(UIColors.accent)
    love.graphics.setLineWidth(2)
    love.graphics.line(x - 8, y, x + 8, y)
    love.graphics.line(x, y - 8, x, y + 8)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Funções auxiliares
function UIManager:drawProgressBar(x, y, w, h, progress, color)
    -- Fundo
    love.graphics.setColor(UIColors.background)
    self:drawRoundedRect(x, y, w, h, 4)
    
    -- Progresso
    love.graphics.setColor(color)
    if progress > 0 then
        self:drawRoundedRect(x, y, w * progress, h, 4)
    end
    
    -- Borda
    love.graphics.setColor(UIColors.textDim)
    love.graphics.setLineWidth(1)
    self:drawRoundedRectOutline(x, y, w, h, 4)
end

function UIManager:drawRoundedRect(x, y, w, h, radius)
    love.graphics.rectangle("fill", x + radius, y, w - radius * 2, h)
    love.graphics.rectangle("fill", x, y + radius, w, h - radius * 2)
    love.graphics.circle("fill", x + radius, y + radius, radius)
    love.graphics.circle("fill", x + w - radius, y + radius, radius)
    love.graphics.circle("fill", x + radius, y + h - radius, radius)
    love.graphics.circle("fill", x + w - radius, y + h - radius, radius)
end

function UIManager:drawRoundedRectOutline(x, y, w, h, radius)
    -- Linhas retas
    love.graphics.line(x + radius, y, x + w - radius, y)
    love.graphics.line(x + radius, y + h, x + w - radius, y + h)
    love.graphics.line(x, y + radius, x, y + h - radius)
    love.graphics.line(x + w, y + radius, x + w, y + h - radius)
    
    -- Cantos arredondados
    love.graphics.circle("line", x + radius, y + radius, radius)
    love.graphics.circle("line", x + w - radius, y + radius, radius)
    love.graphics.circle("line", x + radius, y + h - radius, radius)
    love.graphics.circle("line", x + w - radius, y + h - radius, radius)
end

function UIManager:wrapText(text, maxWidth, font)
    local wrappedText = ""
    local line = ""
    
    for word in text:gmatch("%S+") do
        local testLine = line == "" and word or (line .. " " .. word)
        if font:getWidth(testLine) <= maxWidth then
            line = testLine
        else
            if line ~= "" then
                wrappedText = wrappedText .. line .. "\n"
            end
            line = word
        end
    end
    
    if line ~= "" then
        wrappedText = wrappedText .. line
    end
    
    return wrappedText
end

function UIManager:addNotification(text, color, duration)
    table.insert(self.notifications, {
        text = text,
        color = color or UIColors.text,
        duration = duration or 3.0,
        timer = 0
    })
    
    -- Manter apenas as últimas 5 notificações
    while #self.notifications > 5 do
        table.remove(self.notifications, 1)
    end
end

-- Controle de janelas
function UIManager:toggleWindow(windowName)
    if self.windows[windowName] then
        self.windows[windowName].visible = not self.windows[windowName].visible
    end
end

function UIManager:closeAllWindows()
    for _, window in pairs(self.windows) do
        if window ~= self.windows.hud then
            window.visible = false
        end
    end
end

-- Input handling
function UIManager:keypressed(key)
    if key == "i" then
        self:toggleWindow("inventory")
    elseif key == "t" then
        self:toggleWindow("skillTree")
    elseif key == "a" then
        self:toggleWindow("analysis")
    elseif key == "escape" then
        self:closeAllWindows()
    end
end

function UIManager:mousepressed(x, y, button)
    -- Verificar cliques em janelas
    for name, window in pairs(self.windows) do
        if window.visible and name ~= "hud" then
            -- Botão fechar
            local closeX = window.x + window.width - 40
            local closeY = window.y + 15
            
            if x >= closeX - 12 and x <= closeX + 12 and y >= closeY - 2 and y <= closeY + 22 then
                window.visible = false
                return true
            end
        end
    end
    
    return false
end

return UIManager 