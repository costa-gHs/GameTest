-- sage.lua - Sistema do Sábio Interno
-- Conselheiro AI que analisa situações e fornece conselhos e otimizações

local Sage = {}
local EventBus = require("src.core.eventbus")
local RNG = require("src.core.rng")

-- Níveis de evolução do Sábio
local SageLevel = {
    SABIO = 1,       -- Básico: dicas simples, análise manual
    SABIO_PLUS = 2,  -- Avançado: análise automática, sugestões táticas  
    RAPHAEL = 3      -- Supremo: otimização automática, predição, simulação
}

-- Tipos de conselho
local AdviceType = {
    COMBAT = "combat",
    EXPLORATION = "exploration", 
    PREDATION = "predation",
    ANALYSIS = "analysis",
    CRAFTING = "crafting",
    WARNING = "warning",
    OPTIMIZATION = "optimization"
}

function Sage:new(config)
    local sage = {}
    setmetatable(sage, { __index = self })
    
    sage.level = config.level or SageLevel.SABIO
    sage.hintsEnabled = config.hints or true
    sage.autoAnalysis = config.autoAnalysis or false
    
    -- Sistema de memória do Sábio
    sage.knowledge = {
        enemies = {},        -- Conhecimento sobre inimigos encontrados
        areas = {},          -- Conhecimento sobre áreas exploradas
        strategies = {},     -- Estratégias bem-sucedidas
        failures = {},       -- Análise de falhas
        patterns = {}        -- Padrões detectados
    }
    
    -- Fila de conselhos
    sage.adviceQueue = {}
    sage.currentAdvice = nil
    sage.adviceTimer = 0
    sage.adviceCooldown = 3.0 -- Tempo entre conselhos
    
    -- Estatísticas
    sage.stats = {
        adviceGiven = 0,
        correctPredictions = 0,
        totalPredictions = 0,
        experiencePoints = 0,
        evolutionProgress = 0
    }
    
    -- Templates de mensagens por nível
    sage.messageTemplates = {
        [SageLevel.SABIO] = {
            greeting = "Sistema de Análise ativado. Fornecendo assistência básica.",
            predation = "Alvo identificado. Recomendo cautela durante predação.",
            combat = "Inimigo detectado. Avalie riscos antes de engajar.",
            analysis = "Novos dados disponíveis para análise.",
            evolution = "Acumulando experiência... Evolução possível."
        },
        [SageLevel.SABIO_PLUS] = {
            greeting = "Grande Sábio online. Módulos avançados carregados.",
            predation = "Predação otimizada disponível. Calculando eficiência máxima.",
            combat = "Análise tática: {strategy}. Probabilidade de sucesso: {chance}%.",
            analysis = "Análise automática configurada. Processamento em paralelo.",
            evolution = "Sistemas aprimorados detectados. Integrando capacidades."
        },
        [SageLevel.RAPHAEL] = {
            greeting = "Raphael, Senhor da Sabedoria, ao seu serviço. Computação quântica ativa.",
            predation = "Simulação completa: {outcomes} resultados possíveis. Recomendação: {best}.",
            combat = "Predição de batalha: Vitória garantida com estratégia ótima calculada.",
            analysis = "Meta-análise executada. Padrões ocultos revelados.",
            evolution = "Transcendência detectada. Limites anteriores superados."
        }
    }
    
    return sage
end

-- Update principal do Sábio
function Sage:update(dt, slimeEntity, ecs)
    self.adviceTimer = self.adviceTimer + dt
    
    -- Processar análise automática
    if self.autoAnalysis and self.level >= SageLevel.SABIO_PLUS then
        self:updateAutoAnalysis(dt, slimeEntity, ecs)
    end
    
    -- Gerar conselhos baseados na situação atual
    self:analyzeCurrentSituation(slimeEntity, ecs)
    
    -- Processar fila de conselhos
    self:processAdviceQueue(dt)
    
    -- Atualizar conhecimento
    self:updateKnowledge(slimeEntity, ecs)
    
    -- Verificar evolução
    self:checkEvolution()
end

function Sage:analyzeCurrentSituation(slimeEntity, ecs)
    if self.adviceTimer < self.adviceCooldown then
        return
    end
    
    -- Análise de combate
    local threats = self:detectThreats(slimeEntity, ecs)
    if #threats > 0 then
        self:generateCombatAdvice(slimeEntity, threats, ecs)
    end
    
    -- Análise de predação
    local preyOpportunities = self:detectPreyOpportunities(slimeEntity, ecs)
    if #preyOpportunities > 0 then
        self:generatePredationAdvice(slimeEntity, preyOpportunities, ecs)
    end
    
    -- Análise de otimização
    if self.level >= SageLevel.SABIO_PLUS then
        self:generateOptimizationAdvice(slimeEntity, ecs)
    end
end

function Sage:detectThreats(slimeEntity, ecs)
    local threats = {}
    local slimeTransform = ecs:getComponent(slimeEntity, "Transform")
    if not slimeTransform then return threats end
    
    -- Buscar inimigos próximos
    local enemies = ecs:getEntitiesWith("AI", "Transform", "Health")
    
    for _, enemy in ipairs(enemies) do
        local enemyTransform = ecs:getComponent(enemy, "Transform")
        local enemyAI = ecs:getComponent(enemy, "AI")
        local enemyHealth = ecs:getComponent(enemy, "Health")
        
        local distance = self:calculateDistance(slimeTransform, enemyTransform)
        
        -- Considerar ameaça se estiver próximo ou alerta
        if distance < 100 or enemyAI.state == "alert" then
            table.insert(threats, {
                entity = enemy,
                distance = distance,
                threatLevel = self:calculateThreatLevel(enemy, ecs),
                ai = enemyAI,
                health = enemyHealth
            })
        end
    end
    
    -- Ordenar por nível de ameaça
    table.sort(threats, function(a, b) 
        return a.threatLevel > b.threatLevel 
    end)
    
    return threats
end

function Sage:detectPreyOpportunities(slimeEntity, ecs)
    local opportunities = {}
    local slimeTransform = ecs:getComponent(slimeEntity, "Transform")
    local predationComp = ecs:getComponent(slimeEntity, "Predation")
    
    if not slimeTransform or not predationComp then return opportunities end
    
    -- Buscar alvos possíveis
    local entities = ecs:getEntitiesWith("Transform")
    
    for _, entity in ipairs(entities) do
        if entity ~= slimeEntity then
            local transform = ecs:getComponent(entity, "Transform")
            local distance = self:calculateDistance(slimeTransform, transform)
            
            if distance <= predationComp.range then
                local canPredate = self:canEntityBePreyed(entity, ecs)
                if canPredate then
                    local value = self:calculatePreyValue(entity, ecs)
                    table.insert(opportunities, {
                        entity = entity,
                        distance = distance,
                        value = value,
                        risk = self:calculatePreyRisk(entity, ecs)
                    })
                end
            end
        end
    end
    
    -- Ordenar por valor/risco
    table.sort(opportunities, function(a, b)
        local scoreA = a.value / (a.risk + 0.1)
        local scoreB = b.value / (b.risk + 0.1)
        return scoreA > scoreB
    end)
    
    return opportunities
end

function Sage:generateCombatAdvice(slimeEntity, threats, ecs)
    if #threats == 0 then return end
    
    local primaryThreat = threats[1]
    local advice = {
        type = AdviceType.COMBAT,
        priority = self:calculateAdvicePriority(primaryThreat.threatLevel),
        data = primaryThreat
    }
    
    if self.level == SageLevel.SABIO then
        advice.message = "Inimigo detectado. Distância: " .. math.floor(primaryThreat.distance) .. "px"
        if primaryThreat.threatLevel > 0.7 then
            advice.message = advice.message .. " [ALTA AMEAÇA]"
        end
    elseif self.level == SageLevel.SABIO_PLUS then
        local winChance = self:calculateWinProbability(slimeEntity, primaryThreat.entity, ecs)
        advice.message = string.format("Análise tática: %s. Chance de vitória: %d%%", 
            self:getRecommendedStrategy(winChance), math.floor(winChance * 100))
    else -- RAPHAEL
        local bestStrategy = self:simulateCombatOutcomes(slimeEntity, threats, ecs)
        advice.message = string.format("Estratégia ótima calculada: %s. Execução recomendada.", bestStrategy)
    end
    
    self:queueAdvice(advice)
end

function Sage:generatePredationAdvice(slimeEntity, opportunities, ecs)
    if #opportunities == 0 then return end
    
    local bestOpportunity = opportunities[1]
    local advice = {
        type = AdviceType.PREDATION,
        priority = "medium",
        data = bestOpportunity
    }
    
    if self.level == SageLevel.SABIO then
        advice.message = "Alvo para predação identificado. Valor estimado: " .. bestOpportunity.value
    elseif self.level >= SageLevel.SABIO_PLUS then
        advice.message = string.format("Predação otimizada: Alvo priorizado (Valor: %d, Risco: %.1f)", 
            bestOpportunity.value, bestOpportunity.risk)
        
        if self.level == SageLevel.RAPHAEL then
            local simResults = self:simulatePredation(slimeEntity, bestOpportunity.entity, ecs)
            advice.message = advice.message .. string.format(" | Sim: %d%% sucesso", 
                math.floor(simResults.successRate * 100))
        end
    end
    
    self:queueAdvice(advice)
end

function Sage:generateOptimizationAdvice(slimeEntity, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore then return end
    
    -- Sugerir combinações de traços
    if slimeCore.traits and #slimeCore.traits >= 2 then
        local combinations = self:findOptimalTraitCombinations(slimeCore.traits)
        if #combinations > 0 then
            local advice = {
                type = AdviceType.OPTIMIZATION,
                priority = "low",
                message = "Combinação de traços otimizada disponível: " .. combinations[1].name
            }
            self:queueAdvice(advice)
        end
    end
    
    -- Sugerir formas para situação atual
    if slimeCore.forms and #slimeCore.forms > 0 then
        local recommendedForm = self:recommendFormForSituation(slimeEntity, ecs)
        if recommendedForm then
            local advice = {
                type = AdviceType.OPTIMIZATION,
                priority = "medium",
                message = "Forma recomendada para situação atual: " .. recommendedForm.name
            }
            self:queueAdvice(advice)
        end
    end
end

function Sage:updateAutoAnalysis(dt, slimeEntity, ecs)
    local predationComp = ecs:getComponent(slimeEntity, "Predation")
    if not predationComp or #predationComp.stomach == 0 then
        return
    end
    
    -- Auto-análise quando há itens no estômago
    if #predationComp.stomach >= predationComp.capacity * 0.5 then
        local advice = {
            type = AdviceType.ANALYSIS,
            priority = "high",
            message = "Análise automática recomendada. Estômago: " .. 
                      #predationComp.stomach .. "/" .. predationComp.capacity
        }
        self:queueAdvice(advice)
    end
end

function Sage:calculateDistance(transform1, transform2)
    local dx = transform2.x - transform1.x
    local dy = transform2.y - transform1.y
    return math.sqrt(dx * dx + dy * dy)
end

function Sage:calculateThreatLevel(entity, ecs)
    local baseLevel = 0.3
    
    local health = ecs:getComponent(entity, "Health")
    if health then
        baseLevel = baseLevel + (health.current / health.max) * 0.3
    end
    
    local ai = ecs:getComponent(entity, "AI")
    if ai then
        if ai.state == "alert" then baseLevel = baseLevel + 0.3 end
        if ai.type == "hunter" then baseLevel = baseLevel + 0.2 end
        if ai.type == "guard" then baseLevel = baseLevel + 0.1 end
    end
    
    local combat = ecs:getComponent(entity, "Combat")
    if combat then
        baseLevel = baseLevel + 0.2
    end
    
    return math.min(1.0, baseLevel)
end

function Sage:canEntityBePreyed(entity, ecs)
    -- Básica verificação se pode ser predado
    if ecs:hasComponent(entity, "SlimeCore") then return false end
    
    local health = ecs:getComponent(entity, "Health")
    return not health or health.current <= 0 or 
           ecs:hasComponent(entity, "Item") or 
           ecs:hasComponent(entity, "Lootable")
end

function Sage:calculatePreyValue(entity, ecs)
    local value = 1
    
    local lootable = ecs:getComponent(entity, "Lootable")
    if lootable then
        value = value + (lootable.essence or 0)
        value = value + #(lootable.traits or {}) * 2
    end
    
    local item = ecs:getComponent(entity, "Item")
    if item then
        value = value + (item.value or 0)
    end
    
    return value
end

function Sage:calculatePreyRisk(entity, ecs)
    local risk = 0.1
    
    local health = ecs:getComponent(entity, "Health")
    if health and health.current > 0 then
        risk = risk + 0.5
        
        local ai = ecs:getComponent(entity, "AI")
        if ai and ai.state == "alert" then
            risk = risk + 0.3
        end
    end
    
    return risk
end

function Sage:queueAdvice(advice)
    -- Evitar conselhos duplicados
    for _, existing in ipairs(self.adviceQueue) do
        if existing.type == advice.type and 
           existing.message == advice.message then
            return
        end
    end
    
    table.insert(self.adviceQueue, advice)
    
    -- Manter fila limitada
    if #self.adviceQueue > 5 then
        table.remove(self.adviceQueue, 1)
    end
end

function Sage:processAdviceQueue(dt)
    if #self.adviceQueue == 0 or self.currentAdvice then
        return
    end
    
    -- Pegar conselho de maior prioridade
    table.sort(self.adviceQueue, function(a, b)
        local priorityMap = {high = 3, medium = 2, low = 1}
        return (priorityMap[a.priority] or 1) > (priorityMap[b.priority] or 1)
    end)
    
    self.currentAdvice = table.remove(self.adviceQueue, 1)
    self.adviceTimer = 0
    
    -- Emitir evento de conselho
    EventBus:emit(EventBus.Events.SAGE_ADVICE, {
        advice = self.currentAdvice,
        sageLevel = self.level
    })
    
    self.stats.adviceGiven = self.stats.adviceGiven + 1
    print("[Sábio] " .. self.currentAdvice.message)
end

function Sage:getCurrentAdvice()
    return self.currentAdvice
end

function Sage:dismissCurrentAdvice()
    self.currentAdvice = nil
    self.adviceTimer = 0
end

function Sage:getRecommendedStrategy(winChance)
    if winChance > 0.8 then
        return "Engajamento direto"
    elseif winChance > 0.5 then
        return "Combate cauteloso"
    elseif winChance > 0.3 then
        return "Hit-and-run"
    else
        return "Evasão recomendada"
    end
end

function Sage:calculateWinProbability(slimeEntity, enemyEntity, ecs)
    -- Cálculo simplificado baseado em stats
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    local enemyHealth = ecs:getComponent(enemyEntity, "Health")
    
    local slimeStrength = (slimeCore and slimeCore.health or 100) + 
                         (slimeCore and #(slimeCore.traits or {}) * 10 or 0)
    local enemyStrength = (enemyHealth and enemyHealth.current or 50)
    
    return slimeStrength / (slimeStrength + enemyStrength)
end

function Sage:checkEvolution()
    local requiredXP = {
        [SageLevel.SABIO] = 100,
        [SageLevel.SABIO_PLUS] = 500
    }
    
    if self.level < SageLevel.RAPHAEL and 
       self.stats.experiencePoints >= (requiredXP[self.level] or 0) then
        self:evolve()
    end
end

function Sage:evolve()
    self.level = self.level + 1
    self.stats.experiencePoints = 0
    
    local names = {"Grande Sábio", "Raphael, Senhor da Sabedoria"}
    local newName = names[self.level - 1] or "Sábio Supremo"
    
    EventBus:emit(EventBus.Events.SAGE_EVOLVED, {
        newLevel = self.level,
        newName = newName
    })
    
    print("[EVOLUÇÃO] Sábio evoluiu para: " .. newName)
    
    -- Desbloquear novas funcionalidades
    if self.level == SageLevel.SABIO_PLUS then
        self.autoAnalysis = true
        print("Nova habilidade: Análise Automática")
    elseif self.level == SageLevel.RAPHAEL then
        print("Nova habilidade: Simulação Quântica")
    end
end

function Sage:addExperience(amount)
    self.stats.experiencePoints = self.stats.experiencePoints + amount
end

-- Interface para obter estatísticas
function Sage:getStats()
    return {
        level = self.level,
        experiencePoints = self.stats.experiencePoints,
        adviceGiven = self.stats.adviceGiven,
        correctPredictions = self.stats.correctPredictions,
        totalPredictions = self.stats.totalPredictions,
        accuracy = self.stats.totalPredictions > 0 and 
                  (self.stats.correctPredictions / self.stats.totalPredictions) or 0,
        queueSize = #self.adviceQueue,
        currentAdvice = self.currentAdvice
    }
end

-- Interface para controle manual
function Sage:enableHints(enabled)
    self.hintsEnabled = enabled
end

function Sage:setAutoAnalysis(enabled)
    if self.level >= SageLevel.SABIO_PLUS then
        self.autoAnalysis = enabled
    end
end

return Sage 