-- predation.lua - Sistema de Predação
-- Permite o slime devorar inimigos/objetos para análise posterior

local Predation = {}
local EventBus = require("src.core.eventbus")
local RNG = require("src.core.rng")

-- Estado da predação
local PredationState = {
    IDLE = "idle",
    CHANNELING = "channeling", 
    CONSUMING = "consuming",
    FAILED = "failed"
}

function Predation:new(config)
    local pred = {}
    setmetatable(pred, { __index = self })
    
    pred.config = config.predation
    pred.state = PredationState.IDLE
    pred.target = nil
    pred.channelTimer = 0
    pred.consumeTimer = 0
    pred.stomach = {} -- Fila de itens a serem analisados
    
    -- Estatísticas
    pred.stats = {
        successfulPredations = 0,
        failedPredations = 0,
        totalEssenceGained = 0
    }
    
    return pred
end

-- Tentar iniciar predação em uma entidade
function Predation:startPredation(slimeEntity, targetEntity, ecs)
    if self.state ~= PredationState.IDLE then
        return false, "Predação já em andamento"
    end
    
    local slimeTransform = ecs:getComponent(slimeEntity, "Transform")
    local targetTransform = ecs:getComponent(targetEntity, "Transform")
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    
    if not slimeTransform or not targetTransform or not predationComponent then
        return false, "Componentes necessários não encontrados"
    end
    
    -- Verificar distância
    local dx = targetTransform.x - slimeTransform.x
    local dy = targetTransform.y - slimeTransform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > predationComponent.range then
        return false, "Alvo muito distante"
    end
    
    -- Verificar capacidade do estômago
    if #predationComponent.stomach >= predationComponent.capacity then
        return false, "Estômago cheio"
    end
    
    -- Verificar se o alvo pode ser predado
    if not self:canPredate(targetEntity, ecs) then
        return false, "Alvo não pode ser predado"
    end
    
    -- Iniciar predação
    self.state = PredationState.CHANNELING
    self.target = targetEntity
    self.channelTimer = 0
    
    -- Marcar predação no componente
    predationComponent.channeling = true
    predationComponent.channelTime = 0
    
    EventBus:emit(EventBus.Events.PREDATION_STARTED, {
        slime = slimeEntity,
        target = targetEntity,
        expectedDuration = self:getPredationTime(targetEntity, ecs)
    })
    
    return true, "Predação iniciada"
end

-- Verificar se uma entidade pode ser predada
function Predation:canPredate(entity, ecs)
    -- Verificar se não é o próprio slime
    if ecs:hasComponent(entity, "SlimeCore") then
        return false
    end
    
    -- Verificar se está vivo (inimigos mortos podem ser predados)
    local health = ecs:getComponent(entity, "Health")
    if health and health.current > 0 then
        -- Inimigos vivos são mais difíceis de predar
        local ai = ecs:getComponent(entity, "AI")
        if ai and ai.state == "alert" then
            return RNG:randomBool(0.3) -- 30% chance se alertado
        end
        return RNG:randomBool(0.7) -- 70% chance se não alertado
    end
    
    -- Itens e inimigos mortos sempre podem ser predados
    return ecs:hasComponent(entity, "Item") or ecs:hasComponent(entity, "Lootable")
end

-- Calcular tempo necessário para predação
function Predation:getPredationTime(entity, ecs)
    local baseTime = self.config.channelTime
    
    -- Modificadores baseados no tipo de entidade
    local health = ecs:getComponent(entity, "Health")
    if health and health.current > 0 then
        -- Entidades vivas demoram mais
        baseTime = baseTime * 2.0
        
        -- Inimigos alertados demoram ainda mais
        local ai = ecs:getComponent(entity, "AI")
        if ai and ai.state == "alert" then
            baseTime = baseTime * self.config.alertPenalty
        end
    end
    
    -- Itens pequenos são mais rápidos
    if ecs:hasComponent(entity, "Item") then
        baseTime = baseTime * 0.5
    end
    
    return baseTime
end

-- Update da predação
function Predation:update(dt, slimeEntity, ecs)
    if self.state == PredationState.IDLE then
        return
    end
    
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    if not predationComponent then
        self:cancelPredation(slimeEntity, ecs)
        return
    end
    
    if self.state == PredationState.CHANNELING then
        self:updateChanneling(dt, slimeEntity, ecs)
    elseif self.state == PredationState.CONSUMING then
        self:updateConsuming(dt, slimeEntity, ecs)
    end
end

function Predation:updateChanneling(dt, slimeEntity, ecs)
    self.channelTimer = self.channelTimer + dt
    
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    predationComponent.channelTime = self.channelTimer
    
    local requiredTime = self:getPredationTime(self.target, ecs)
    
    -- Verificar se ainda podemos predar o alvo
    if not self.target or not self.target.active then
        self:cancelPredation(slimeEntity, ecs, "Alvo desapareceu")
        return
    end
    
    -- Verificar distância
    local slimeTransform = ecs:getComponent(slimeEntity, "Transform")
    local targetTransform = ecs:getComponent(self.target, "Transform")
    
    if slimeTransform and targetTransform then
        local dx = targetTransform.x - slimeTransform.x
        local dy = targetTransform.y - slimeTransform.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > predationComponent.range * 1.2 then -- 20% tolerância
            self:cancelPredation(slimeEntity, ecs, "Alvo muito distante")
            return
        end
    end
    
    -- Verificar se completou o channeling
    if self.channelTimer >= requiredTime then
        self:completePredation(slimeEntity, ecs)
    end
end

function Predation:updateConsuming(dt, slimeEntity, ecs)
    self.consumeTimer = self.consumeTimer + dt
    
    -- Consumo é rápido (animação)
    if self.consumeTimer >= 0.5 then
        self:finishPredation(slimeEntity, ecs)
    end
end

function Predation:completePredation(slimeEntity, ecs)
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    
    -- Extrair informações do alvo
    local preyData = self:extractPreyData(self.target, ecs)
    
    -- Adicionar ao estômago
    table.insert(predationComponent.stomach, preyData)
    
    -- Remover alvo do mundo
    ecs:removeEntity(self.target)
    
    -- Transicionar para consumo (animação)
    self.state = PredationState.CONSUMING
    self.consumeTimer = 0
    
    EventBus:emit(EventBus.Events.PREDATION_COMPLETED, {
        slime = slimeEntity,
        preyData = preyData
    })
    
    self.stats.successfulPredations = self.stats.successfulPredations + 1
end

function Predation:extractPreyData(entity, ecs)
    local data = {
        id = entity.id,
        type = "unknown",
        timestamp = love.timer.getTime(),
        traits = {},
        essence = 0,
        forms = {},
        recipes = {}
    }
    
    -- Determinar tipo
    if ecs:hasComponent(entity, "Item") then
        data.type = "item"
        local item = ecs:getComponent(entity, "Item")
        data.subtype = item.type
        data.essence = item.value or 0
    elseif ecs:hasComponent(entity, "Lootable") then
        data.type = "creature"
        local lootable = ecs:getComponent(entity, "Lootable")
        data.essence = lootable.essence or 0
        data.traits = lootable.traits or {}
        
        -- Determinar tipo de criatura pela AI
        local ai = ecs:getComponent(entity, "AI")
        if ai then
            data.subtype = ai.type
        end
    end
    
    -- Extrair traços físicos (cor, tamanho, etc.)
    local sprite = ecs:getComponent(entity, "Sprite")
    if sprite then
        data.appearance = {
            color = sprite.color,
            size = sprite.size,
            texture = sprite.texture
        }
    end
    
    -- Extrair capacidades de combate
    local combat = ecs:getComponent(entity, "Combat")
    if combat then
        table.insert(data.traits, "combat_" .. (combat.type or "basic"))
    end
    
    -- Extrair capacidades de movimento
    local velocity = ecs:getComponent(entity, "Velocity")
    if velocity and velocity.maxSpeed > 80 then
        table.insert(data.traits, "fast_movement")
    end
    
    return data
end

function Predation:cancelPredation(slimeEntity, ecs, reason)
    self.state = PredationState.IDLE
    self.target = nil
    self.channelTimer = 0
    
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    if predationComponent then
        predationComponent.channeling = false
        predationComponent.channelTime = 0
    end
    
    EventBus:emit(EventBus.Events.PREDATION_FAILED, {
        slime = slimeEntity,
        reason = reason or "Cancelado"
    })
    
    self.stats.failedPredations = self.stats.failedPredations + 1
end

function Predation:finishPredation(slimeEntity, ecs)
    self.state = PredationState.IDLE
    self.target = nil
    self.channelTimer = 0
    self.consumeTimer = 0
    
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    if predationComponent then
        predationComponent.channeling = false
        predationComponent.channelTime = 0
    end
end

-- Interface para controle manual
function Predation:tryPredateAt(slimeEntity, x, y, ecs)
    if self.state ~= PredationState.IDLE then
        return false, "Predação já em andamento"
    end
    
    -- Encontrar entidade mais próxima do ponto
    local target = self:findTargetAt(x, y, ecs, slimeEntity)
    
    if target then
        return self:startPredation(slimeEntity, target, ecs)
    else
        return false, "Nenhum alvo válido encontrado"
    end
end

function Predation:findTargetAt(x, y, ecs, slimeEntity)
    local closestTarget = nil
    local closestDistance = math.huge
    
    -- Buscar em todas as entidades com posição
    local entities = ecs:getEntitiesWith("Transform")
    
    for _, entity in ipairs(entities) do
        if entity ~= slimeEntity then
            local transform = ecs:getComponent(entity, "Transform")
            local dx = transform.x - x
            local dy = transform.y - y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            -- Verificar se está dentro do range de predação
            local predationComp = ecs:getComponent(slimeEntity, "Predation")
            if distance <= predationComp.range and distance < closestDistance then
                if self:canPredate(entity, ecs) then
                    closestTarget = entity
                    closestDistance = distance
                end
            end
        end
    end
    
    return closestTarget
end

-- Obter progresso da predação atual
function Predation:getPredationProgress(slimeEntity, ecs)
    if self.state ~= PredationState.CHANNELING then
        return 0
    end
    
    local requiredTime = self:getPredationTime(self.target, ecs)
    return math.min(1.0, self.channelTimer / requiredTime)
end

-- Verificar se pode iniciar predação
function Predation:canStartPredation(slimeEntity, ecs)
    return self.state == PredationState.IDLE
end

-- Obter conteúdo do estômago
function Predation:getStomachContents(slimeEntity, ecs)
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    return predationComponent and predationComponent.stomach or {}
end

-- Estatísticas
function Predation:getStats()
    return {
        state = self.state,
        successfulPredations = self.stats.successfulPredations,
        failedPredations = self.stats.failedPredations,
        successRate = self.stats.successfulPredations / math.max(1, self.stats.successfulPredations + self.stats.failedPredations),
        totalEssenceGained = self.stats.totalEssenceGained
    }
end

return Predation 