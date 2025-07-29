-- analysis.lua - Sistema de Análise 
-- Processa itens devorados para extrair traços, formas e receitas

local Analysis = {}
local EventBus = require("src.core.eventbus")
local RNG = require("src.core.rng")

-- Estados de análise
local AnalysisState = {
    IDLE = "idle",
    ANALYZING = "analyzing",
    COMPLETED = "completed"
}

function Analysis:new(config)
    local analysis = {}
    setmetatable(analysis, { __index = self })
    
    analysis.config = config.predation
    analysis.state = AnalysisState.IDLE
    analysis.queue = {} -- Fila de análise
    analysis.currentItem = nil
    analysis.analysisTimer = 0
    analysis.discoveries = {} -- Cache de descobertas
    
    -- Database de traços conhecidos
    analysis.knownTraits = {}
    analysis.knownForms = {}
    analysis.knownRecipes = {}
    
    -- Estatísticas
    analysis.stats = {
        itemsAnalyzed = 0,
        traitsDiscovered = 0,
        formsDiscovered = 0,
        recipesDiscovered = 0,
        analysisTime = 0
    }
    
    return analysis
end

-- Iniciar análise dos itens no estômago
function Analysis:startAnalysis(slimeEntity, ecs)
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    if not predationComponent or #predationComponent.stomach == 0 then
        return false, "Nenhum item para analisar"
    end
    
    if self.state == AnalysisState.ANALYZING then
        return false, "Análise já em andamento"
    end
    
    -- Copiar itens do estômago para fila de análise
    self.queue = {}
    for _, item in ipairs(predationComponent.stomach) do
        table.insert(self.queue, item)
    end
    
    -- Limpar estômago
    predationComponent.stomach = {}
    
    -- Iniciar primeira análise
    self:startNextAnalysis(slimeEntity, ecs)
    
    EventBus:emit(EventBus.Events.ANALYSIS_STARTED, {
        slime = slimeEntity,
        itemCount = #self.queue
    })
    
    return true, "Análise iniciada"
end

function Analysis:startNextAnalysis(slimeEntity, ecs)
    if #self.queue == 0 then
        self.state = AnalysisState.COMPLETED
        self:completeAnalysis(slimeEntity, ecs)
        return
    end
    
    -- Pegar próximo item da fila
    self.currentItem = table.remove(self.queue, 1)
    self.state = AnalysisState.ANALYZING
    self.analysisTimer = 0
    
    print("Analisando: " .. self.currentItem.type .. " (" .. (#self.queue + 1) .. " restantes)")
end

function Analysis:update(dt, slimeEntity, ecs)
    if self.state ~= AnalysisState.ANALYZING then
        return
    end
    
    self.analysisTimer = self.analysisTimer + dt
    self.stats.analysisTime = self.stats.analysisTime + dt
    
    local analysisRate = self.config.analysisRate
    
    -- Acelerar análise baseado no nível do Sábio
    local sageComponent = ecs:getComponent(slimeEntity, "Analysis")
    if sageComponent and sageComponent.sageLevel > 1 then
        analysisRate = analysisRate * (1 + (sageComponent.sageLevel - 1) * 0.5)
    end
    
    -- Completar análise
    if self.analysisTimer >= (1.0 / analysisRate) then
        self:completeCurrentAnalysis(slimeEntity, ecs)
        self:startNextAnalysis(slimeEntity, ecs)
    end
end

function Analysis:completeCurrentAnalysis(slimeEntity, ecs)
    if not self.currentItem then return end
    
    local discoveries = self:analyzeItem(self.currentItem)
    
    -- Aplicar descobertas ao slime
    self:applyDiscoveries(slimeEntity, discoveries, ecs)
    
    -- Armazenar descobertas
    table.insert(self.discoveries, {
        item = self.currentItem,
        discoveries = discoveries,
        timestamp = love.timer.getTime()
    })
    
    self.stats.itemsAnalyzed = self.stats.itemsAnalyzed + 1
    
    print("Análise completa: " .. #discoveries.traits .. " traços, " .. 
          #discoveries.forms .. " formas, " .. #discoveries.recipes .. " receitas")
end

function Analysis:analyzeItem(item)
    local discoveries = {
        traits = {},
        forms = {},
        recipes = {},
        essence = item.essence or 0
    }
    
    -- Análise baseada no tipo
    if item.type == "creature" then
        discoveries = self:analyzeCreature(item, discoveries)
    elseif item.type == "item" then
        discoveries = self:analyzeItemObject(item, discoveries)
    end
    
    -- Chance de descobrir receitas (combinações)
    discoveries.recipes = self:discoverRecipes(item, discoveries)
    
    return discoveries
end

function Analysis:analyzeCreature(item, discoveries)
    -- Traços básicos de criatura
    table.insert(discoveries.traits, {
        id = "basic_anatomy",
        name = "Anatomia Básica",
        description = "Conhecimento básico de estrutura corporal",
        rarity = "common",
        effects = { health_bonus = 5 }
    })
    
    -- Traços específicos baseados no subtipo
    if item.subtype == "wanderer" then
        table.insert(discoveries.traits, {
            id = "wandering_instinct",
            name = "Instinto Errante", 
            description = "Melhora navegação e detecção de caminhos",
            rarity = "common",
            effects = { movement_speed = 1.1, path_finding = true }
        })
    elseif item.subtype == "guard" then
        table.insert(discoveries.traits, {
            id = "defensive_stance",
            name = "Postura Defensiva",
            description = "Reduz dano recebido quando parado",
            rarity = "uncommon", 
            effects = { damage_reduction = 0.15, defense_bonus = true }
        })
    elseif item.subtype == "hunter" then
        table.insert(discoveries.traits, {
            id = "predator_senses",
            name = "Sentidos Predadores",
            description = "Aumenta range de detecção de inimigos",
            rarity = "uncommon",
            effects = { detection_range = 1.5, stealth_detection = true }
        })
    end
    
    -- Traços dos dados originais
    for _, traitName in ipairs(item.traits or {}) do
        local trait = self:createTraitFromName(traitName)
        if trait then
            table.insert(discoveries.traits, trait)
        end
    end
    
    -- Forma de mimetismo baseada na aparência
    if item.appearance then
        local form = {
            id = item.subtype .. "_form",
            name = "Forma de " .. (item.subtype or "Criatura"),
            description = "Permite mimetizar aparência da criatura por tempo limitado",
            rarity = self:getFormRarity(item.subtype),
            duration = 30, -- segundos
            cooldown = 60,
            stats = {
                health_modifier = 1.0,
                speed_modifier = 1.0,
                size_modifier = 1.0
            },
            appearance = item.appearance
        }
        
        -- Modificadores específicos
        if item.subtype == "hunter" then
            form.stats.speed_modifier = 1.2
            form.stats.size_modifier = 0.9
        elseif item.subtype == "guard" then
            form.stats.health_modifier = 1.3
            form.stats.speed_modifier = 0.8
        end
        
        table.insert(discoveries.forms, form)
    end
    
    return discoveries
end

function Analysis:analyzeItemObject(item, discoveries)
    -- Traços baseados no tipo de item
    if item.subtype == "essence" then
        table.insert(discoveries.traits, {
            id = "essence_affinity",
            name = "Afinidade com Essência",
            description = "Melhora absorção de essência",
            rarity = "common",
            effects = { essence_gain = 1.1 }
        })
    elseif item.subtype == "crystal" then
        table.insert(discoveries.traits, {
            id = "crystalline_structure",
            name = "Estrutura Cristalina",
            description = "Melhora resistência mágica",
            rarity = "uncommon",
            effects = { magic_resistance = 0.2, mana_efficiency = 1.1 }
        })
    elseif item.subtype == "herb" then
        table.insert(discoveries.traits, {
            id = "natural_regeneration",
            name = "Regeneração Natural",
            description = "Regenera HP lentamente ao longo do tempo",
            rarity = "common",
            effects = { health_regen = 0.5 }
        })
    end
    
    return discoveries
end

function Analysis:createTraitFromName(traitName)
    -- Converter nomes de traços em objetos de traço completos
    local traitDatabase = {
        basic_combat = {
            id = "basic_combat",
            name = "Combate Básico",
            description = "Conhecimento fundamental de combate",
            rarity = "common",
            effects = { attack_damage = 1.1 }
        },
        fast_movement = {
            id = "fast_movement", 
            name = "Movimento Rápido",
            description = "Velocidade de movimento aumentada",
            rarity = "common",
            effects = { movement_speed = 1.2 }
        },
        stealth = {
            id = "stealth",
            name = "Furtividade",
            description = "Reduz detecção por inimigos",
            rarity = "uncommon",
            effects = { stealth_bonus = 0.3, detection_reduction = 0.5 }
        }
    }
    
    return traitDatabase[traitName]
end

function Analysis:discoverRecipes(item, discoveries)
    local recipes = {}
    
    -- Chance de descobrir receitas baseada na raridade dos traços
    local recipeChance = 0.1 -- 10% base
    
    for _, trait in ipairs(discoveries.traits) do
        if trait.rarity == "uncommon" then
            recipeChance = recipeChance + 0.1
        elseif trait.rarity == "rare" then
            recipeChance = recipeChance + 0.2
        end
    end
    
    if RNG:randomBool(recipeChance) then
        -- Gerar receita básica
        local recipe = {
            id = "fusion_" .. item.type .. "_" .. (item.subtype or "basic"),
            name = "Fusão de " .. (item.subtype or item.type),
            description = "Combina traços para criar habilidade única",
            ingredients = {},
            result = {
                type = "skill",
                power = math.random(1, 3)
            },
            rarity = "uncommon"
        }
        
        -- Adicionar ingredientes baseados nos traços descobertos
        for i = 1, math.min(2, #discoveries.traits) do
            table.insert(recipe.ingredients, {
                type = "trait",
                id = discoveries.traits[i].id,
                quantity = 1
            })
        end
        
        table.insert(recipes, recipe)
    end
    
    return recipes
end

function Analysis:getFormRarity(subtype)
    local rarityMap = {
        wanderer = "common",
        guard = "uncommon", 
        hunter = "uncommon",
        mage = "rare",
        boss = "legendary"
    }
    
    return rarityMap[subtype] or "common"
end

function Analysis:applyDiscoveries(slimeEntity, discoveries, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore then return end
    
    -- Aplicar essência
    slimeCore.essence = slimeCore.essence + discoveries.essence
    
    -- Adicionar traços descobertos
    if not slimeCore.traits then slimeCore.traits = {} end
    for _, trait in ipairs(discoveries.traits) do
        if not self:hasTraitId(slimeCore.traits, trait.id) then
            table.insert(slimeCore.traits, trait)
            self.knownTraits[trait.id] = trait
            self.stats.traitsDiscovered = self.stats.traitsDiscovered + 1
            
            EventBus:emit(EventBus.Events.TRAIT_DISCOVERED, {
                slime = slimeEntity,
                trait = trait
            })
        end
    end
    
    -- Adicionar formas descobertas
    if not slimeCore.forms then slimeCore.forms = {} end
    for _, form in ipairs(discoveries.forms) do
        if not self:hasFormId(slimeCore.forms, form.id) then
            table.insert(slimeCore.forms, form)
            self.knownForms[form.id] = form
            self.stats.formsDiscovered = self.stats.formsDiscovered + 1
        end
    end
    
    -- Adicionar receitas descobertas
    if not slimeCore.recipes then slimeCore.recipes = {} end
    for _, recipe in ipairs(discoveries.recipes) do
        if not self:hasRecipeId(slimeCore.recipes, recipe.id) then
            table.insert(slimeCore.recipes, recipe)
            self.knownRecipes[recipe.id] = recipe
            self.stats.recipesDiscovered = self.stats.recipesDiscovered + 1
        end
    end
end

function Analysis:hasTraitId(traits, id)
    for _, trait in ipairs(traits) do
        if trait.id == id then return true end
    end
    return false
end

function Analysis:hasFormId(forms, id)
    for _, form in ipairs(forms) do
        if form.id == id then return true end
    end
    return false
end

function Analysis:hasRecipeId(recipes, id)
    for _, recipe in ipairs(recipes) do
        if recipe.id == id then return true end
    end
    return false
end

function Analysis:completeAnalysis(slimeEntity, ecs)
    self.state = AnalysisState.IDLE
    self.currentItem = nil
    self.analysisTimer = 0
    
    EventBus:emit(EventBus.Events.ANALYSIS_COMPLETED, {
        slime = slimeEntity,
        discoveries = self.discoveries
    })
    
    print("Análise completa! " .. #self.discoveries .. " itens processados")
    
    -- Limpar descobertas antigas (manter apenas as últimas 10)
    while #self.discoveries > 10 do
        table.remove(self.discoveries, 1)
    end
end

-- Interface para análise automática
function Analysis:canAutoAnalyze(slimeEntity, ecs)
    local analysisComponent = ecs:getComponent(slimeEntity, "Analysis")
    return analysisComponent and analysisComponent.autoAnalysis
end

function Analysis:getAnalysisProgress()
    if self.state ~= AnalysisState.ANALYZING then
        return 0, 0
    end
    
    local totalItems = #self.queue + 1 -- +1 para o item atual
    local completedItems = self.stats.itemsAnalyzed
    local currentProgress = self.analysisTimer * self.config.analysisRate
    
    return currentProgress, completedItems, totalItems
end

-- Obter informações sobre descobertas recentes
function Analysis:getRecentDiscoveries(count)
    count = count or 5
    local recent = {}
    local startIndex = math.max(1, #self.discoveries - count + 1)
    
    for i = startIndex, #self.discoveries do
        table.insert(recent, self.discoveries[i])
    end
    
    return recent
end

-- Estatísticas
function Analysis:getStats()
    return {
        state = self.state,
        queueSize = #self.queue,
        itemsAnalyzed = self.stats.itemsAnalyzed,
        traitsDiscovered = self.stats.traitsDiscovered,
        formsDiscovered = self.stats.formsDiscovered,
        recipesDiscovered = self.stats.recipesDiscovered,
        analysisTime = self.stats.analysisTime,
        knownTraits = self.knownTraits,
        knownForms = self.knownForms,
        knownRecipes = self.knownRecipes
    }
end

-- Verificar se pode iniciar análise
function Analysis:canStartAnalysis(slimeEntity, ecs)
    if self.state == AnalysisState.ANALYZING then
        return false, "Análise já em andamento"
    end
    
    local predationComponent = ecs:getComponent(slimeEntity, "Predation")
    if not predationComponent or #predationComponent.stomach == 0 then
        return false, "Nenhum item para analisar"
    end
    
    return true, "Pronto para análise"
end

return Analysis 