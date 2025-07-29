-- slime.lua - Controller principal do slime
-- Integra sistemas de predação, análise, mimetismo e sábio

local SlimeController = {}
local EventBus = require("src.core.eventbus")
local Predation = require("src.gameplay.predation")
local Analysis = require("src.gameplay.analysis")
local Sage = require("src.gameplay.sage")

function SlimeController:new(config)
    local slime = {}
    setmetatable(slime, { __index = self })
    
    slime.config = config
    slime.entity = nil -- Será definido quando criar a entidade
    
    -- Subsistemas
    slime.predation = Predation:new(config)
    slime.analysis = Analysis:new(config)
    slime.sage = Sage:new(config.sage)
    
    -- Estado do slime
    slime.state = "normal" -- normal, predating, analyzing, mimicking
    slime.currentForm = "base"
    slime.mimicryTimer = 0
    slime.mimicryDuration = 0
    
    -- Configurar eventos
    self:setupEventListeners(slime)
    
    return slime
end

function SlimeController:setupEventListeners(slime)
    -- Eventos de predação
    EventBus:on(EventBus.Events.PREDATION_STARTED, function(data)
        if data.slime == slime.entity then
            slime.state = "predating"
            slime.sage:addExperience(1)
        end
    end)
    
    EventBus:on(EventBus.Events.PREDATION_COMPLETED, function(data)
        if data.slime == slime.entity then
            slime.state = "normal"
            slime.sage:addExperience(5)
            
            -- Auto-análise se habilitada
            if slime.analysis:canAutoAnalyze(slime.entity, slime.ecs) then
                slime.analysis:startAnalysis(slime.entity, slime.ecs)
            end
        end
    end)
    
    EventBus:on(EventBus.Events.PREDATION_FAILED, function(data)
        if data.slime == slime.entity then
            slime.state = "normal"
        end
    end)
    
    -- Eventos de análise
    EventBus:on(EventBus.Events.ANALYSIS_STARTED, function(data)
        if data.slime == slime.entity then
            slime.state = "analyzing"
        end
    end)
    
    EventBus:on(EventBus.Events.ANALYSIS_COMPLETED, function(data)
        if data.slime == slime.entity then
            slime.state = "normal"
            slime.sage:addExperience(3)
        end
    end)
    
    EventBus:on(EventBus.Events.TRAIT_DISCOVERED, function(data)
        if data.slime == slime.entity then
            print("Novo traço descoberto: " .. data.trait.name)
            slime.sage:addExperience(2)
        end
    end)
    
    -- Eventos do sábio
    EventBus:on(EventBus.Events.SAGE_ADVICE, function(data)
        -- Processar conselho do sábio
        print("[Sábio] " .. data.advice.message)
    end)
end

function SlimeController:setEntity(entity, ecs)
    self.entity = entity
    self.ecs = ecs
end

function SlimeController:update(dt)
    if not self.entity or not self.ecs then return end
    
    -- Atualizar subsistemas
    self.predation:update(dt, self.entity, self.ecs)
    self.analysis:update(dt, self.entity, self.ecs)
    self.sage:update(dt, self.entity, self.ecs)
    
    -- Atualizar mimetismo
    self:updateMimicry(dt)
    
    -- Aplicar efeitos de traços ativos
    self:applyTraitEffects(dt)
end

function SlimeController:updateMimicry(dt)
    if self.currentForm ~= "base" then
        self.mimicryTimer = self.mimicryTimer + dt
        
        if self.mimicryTimer >= self.mimicryDuration then
            self:revertForm()
        end
    end
end

function SlimeController:applyTraitEffects(dt)
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    if not slimeCore or not slimeCore.traits then return end
    
    local velocity = self.ecs:getComponent(self.entity, "Velocity")
    local health = slimeCore
    
    -- Aplicar efeitos de traços
    for _, trait in ipairs(slimeCore.traits) do
        if trait.effects then
            -- Movimento
            if trait.effects.movement_speed and velocity then
                velocity.maxSpeed = (velocity.baseMaxSpeed or 120) * trait.effects.movement_speed
            end
            
            -- Regeneração
            if trait.effects.health_regen then
                health.health = math.min(health.maxHealth, 
                    health.health + trait.effects.health_regen * dt)
            end
            
            -- Ganho de essência
            if trait.effects.essence_gain then
                -- Modificador aplicado quando coletar essência
            end
        end
    end
end

function SlimeController:tryPredation(targetX, targetY)
    if self.state ~= "normal" then
        return false, "Slime ocupado"
    end
    
    return self.predation:tryPredateAt(self.entity, targetX, targetY, self.ecs)
end

function SlimeController:startAnalysis()
    if self.state ~= "normal" then
        return false, "Slime ocupado"
    end
    
    return self.analysis:startAnalysis(self.entity, self.ecs)
end

function SlimeController:mimicForm(formId)
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    if not slimeCore or not slimeCore.forms then
        return false, "Nenhuma forma disponível"
    end
    
    -- Encontrar forma
    local targetForm = nil
    for _, form in ipairs(slimeCore.forms) do
        if form.id == formId then
            targetForm = form
            break
        end
    end
    
    if not targetForm then
        return false, "Forma não encontrada"
    end
    
    -- Verificar cooldown
    if targetForm.lastUsed and 
       love.timer.getTime() - targetForm.lastUsed < targetForm.cooldown then
        return false, "Forma em cooldown"
    end
    
    -- Aplicar forma
    self:applyForm(targetForm)
    return true, "Forma ativada: " .. targetForm.name
end

function SlimeController:applyForm(form)
    if self.currentForm ~= "base" then
        self:revertForm()
    end
    
    self.currentForm = form.id
    self.mimicryTimer = 0
    self.mimicryDuration = form.duration
    form.lastUsed = love.timer.getTime()
    
    -- Aplicar modificadores da forma
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    local velocity = self.ecs:getComponent(self.entity, "Velocity")
    local sprite = self.ecs:getComponent(self.entity, "Sprite")
    
    if slimeCore then
        -- Backup stats originais
        if not slimeCore.baseStats then
            slimeCore.baseStats = {
                maxHealth = slimeCore.maxHealth,
                health = slimeCore.health
            }
        end
        
        -- Aplicar modificadores
        slimeCore.maxHealth = slimeCore.baseStats.maxHealth * form.stats.health_modifier
        slimeCore.health = math.min(slimeCore.health, slimeCore.maxHealth)
    end
    
    if velocity then
        if not velocity.baseMaxSpeed then
            velocity.baseMaxSpeed = velocity.maxSpeed
        end
        velocity.maxSpeed = velocity.baseMaxSpeed * form.stats.speed_modifier
    end
    
    if sprite and form.appearance then
        -- Backup aparência original
        if not sprite.baseAppearance then
            sprite.baseAppearance = {
                color = {sprite.color[1], sprite.color[2], sprite.color[3], sprite.color[4]},
                size = sprite.size
            }
        end
        
        -- Aplicar nova aparência
        sprite.color = form.appearance.color or sprite.color
        sprite.size = (sprite.baseAppearance.size or sprite.size) * form.stats.size_modifier
    end
    
    print("Forma ativada: " .. form.name .. " (" .. form.duration .. "s)")
end

function SlimeController:revertForm()
    if self.currentForm == "base" then return end
    
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    local velocity = self.ecs:getComponent(self.entity, "Velocity")
    local sprite = self.ecs:getComponent(self.entity, "Sprite")
    
    -- Restaurar stats
    if slimeCore and slimeCore.baseStats then
        local healthRatio = slimeCore.health / slimeCore.maxHealth
        slimeCore.maxHealth = slimeCore.baseStats.maxHealth
        slimeCore.health = slimeCore.maxHealth * healthRatio
    end
    
    if velocity and velocity.baseMaxSpeed then
        velocity.maxSpeed = velocity.baseMaxSpeed
    end
    
    if sprite and sprite.baseAppearance then
        sprite.color = sprite.baseAppearance.color
        sprite.size = sprite.baseAppearance.size
    end
    
    print("Forma revertida para normal")
    self.currentForm = "base"
    self.mimicryTimer = 0
    self.mimicryDuration = 0
end

function SlimeController:getAvailableForms()
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    if not slimeCore or not slimeCore.forms then return {} end
    
    local availableForms = {}
    local currentTime = love.timer.getTime()
    
    for _, form in ipairs(slimeCore.forms) do
        local cooldownRemaining = 0
        if form.lastUsed then
            cooldownRemaining = math.max(0, form.cooldown - (currentTime - form.lastUsed))
        end
        
        table.insert(availableForms, {
            form = form,
            available = cooldownRemaining == 0,
            cooldownRemaining = cooldownRemaining
        })
    end
    
    return availableForms
end

function SlimeController:getTraitsByCategory()
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    if not slimeCore or not slimeCore.traits then return {} end
    
    local categories = {
        combat = {},
        movement = {},
        utility = {},
        passive = {}
    }
    
    for _, trait in ipairs(slimeCore.traits) do
        local category = "passive"
        
        if trait.effects then
            if trait.effects.attack_damage or trait.effects.defense_bonus then
                category = "combat"
            elseif trait.effects.movement_speed or trait.effects.path_finding then
                category = "movement"
            elseif trait.effects.essence_gain or trait.effects.stealth_bonus then
                category = "utility"
            end
        end
        
        table.insert(categories[category], trait)
    end
    
    return categories
end

function SlimeController:getPredationProgress()
    return self.predation:getPredationProgress(self.entity, self.ecs)
end

function SlimeController:getAnalysisProgress()
    return self.analysis:getAnalysisProgress()
end

function SlimeController:getCurrentAdvice()
    return self.sage:getCurrentAdvice()
end

function SlimeController:dismissAdvice()
    self.sage:dismissCurrentAdvice()
end

function SlimeController:getStats()
    local slimeCore = self.ecs:getComponent(self.entity, "SlimeCore")
    
    return {
        state = self.state,
        currentForm = self.currentForm,
        mimicryTimer = self.mimicryTimer,
        essence = slimeCore and slimeCore.essence or 0,
        health = slimeCore and slimeCore.health or 0,
        maxHealth = slimeCore and slimeCore.maxHealth or 100,
        traitCount = slimeCore and slimeCore.traits and #slimeCore.traits or 0,
        formCount = slimeCore and slimeCore.forms and #slimeCore.forms or 0,
        predation = self.predation:getStats(),
        analysis = self.analysis:getStats(),
        sage = self.sage:getStats()
    }
end

function SlimeController:reset()
    -- Reset para novo run
    self.state = "normal"
    self.currentForm = "base"
    self.mimicryTimer = 0
    self.mimicryDuration = 0
    
    -- Manter conhecimento do sábio, mas resetar outros stats
    self.predation = Predation:new(self.config)
    self.analysis = Analysis:new(self.config)
    
    print("Slime resetado para novo run")
end

function SlimeController:keypressed(key)
    if key == "space" then
        if self.entity then
            local transform = self.ecs:getComponent(self.entity, "Transform")
            if transform then
                local success, msg = self:tryPredation(transform.x, transform.y)
                print("Predação: " .. msg)
            end
        end
    elseif key == "a" then
        local success, msg = self:startAnalysis()
        print("Análise: " .. msg)
    elseif key == "q" then
        -- Ciclar formas disponíveis
        local forms = self:getAvailableForms()
        for _, formData in ipairs(forms) do
            if formData.available then
                local success, msg = self:mimicForm(formData.form.id)
                print("Mimetismo: " .. msg)
                break
            end
        end
    elseif key == "e" then
        -- Reverter forma
        if self.currentForm ~= "base" then
            self:revertForm()
        end
    elseif key == "tab" then
        -- Dispensar conselho atual
        self:dismissAdvice()
    end
end

function SlimeController:mousepressed(x, y, button)
    if button == 1 then
        -- Converter coordenadas da tela para mundo
        local camera = _G.camera or {x = 0, y = 0, scale = 1}
        local worldX = (x - love.graphics.getWidth() / 2) / camera.scale + camera.x
        local worldY = (y - love.graphics.getHeight() / 2) / camera.scale + camera.y
        
        local success, msg = self:tryPredation(worldX, worldY)
        print("Predação: " .. msg)
    end
end

return SlimeController 