-- ecs.lua - Entity Component System
-- Sistema para gerenciar entidades, componentes e sistemas de forma modular

local ECS = {}

-- Registry para armazenar todas as entidades e componentes
local entityCounter = 0
local entities = {}
local components = {}
local systems = {}
local entityGroups = {} -- Cache para queries de entidades

-- Função para criar nova entidade
function ECS:createEntity()
    entityCounter = entityCounter + 1
    local entity = {
        id = entityCounter,
        active = true,
        components = {}
    }
    
    entities[entityCounter] = entity
    return entity
end

-- Remover entidade
function ECS:removeEntity(entity)
    if type(entity) == "number" then
        entity = entities[entity]
    end
    
    if entity then
        -- Remover todos os componentes
        for componentType, _ in pairs(entity.components) do
            self:removeComponent(entity, componentType)
        end
        
        entities[entity.id] = nil
        entity.active = false
        
        -- Limpar cache de grupos
        entityGroups = {}
    end
end

-- Adicionar componente à entidade
function ECS:addComponent(entity, componentType, componentData)
    if type(entity) == "number" then
        entity = entities[entity]
    end
    
    if not entity then return false end
    
    -- Inicializar storage do componente se necessário
    if not components[componentType] then
        components[componentType] = {}
    end
    
    -- Adicionar component data
    components[componentType][entity.id] = componentData or {}
    entity.components[componentType] = true
    
    -- Limpar cache de grupos
    entityGroups = {}
    
    return true
end

-- Remover componente da entidade
function ECS:removeComponent(entity, componentType)
    if type(entity) == "number" then
        entity = entities[entity]
    end
    
    if not entity then return false end
    
    if components[componentType] then
        components[componentType][entity.id] = nil
    end
    
    entity.components[componentType] = nil
    
    -- Limpar cache de grupos
    entityGroups = {}
    
    return true
end

-- Obter componente de uma entidade
function ECS:getComponent(entity, componentType)
    if type(entity) == "number" then
        entity = entities[entity]
    end
    
    if not entity then return nil end
    
    if components[componentType] then
        return components[componentType][entity.id]
    end
    
    return nil
end

-- Verificar se entidade possui componente
function ECS:hasComponent(entity, componentType)
    if type(entity) == "number" then
        entity = entities[entity]
    end
    
    if not entity then return false end
    
    return entity.components[componentType] == true
end

-- Query para encontrar entidades com componentes específicos
function ECS:getEntitiesWith(...)
    local requiredComponents = {...}
    local cacheKey = table.concat(requiredComponents, ",")
    
    -- Verificar cache
    if entityGroups[cacheKey] then
        return entityGroups[cacheKey]
    end
    
    local result = {}
    
    for entityId, entity in pairs(entities) do
        if entity.active then
            local hasAll = true
            for _, componentType in ipairs(requiredComponents) do
                if not entity.components[componentType] then
                    hasAll = false
                    break
                end
            end
            
            if hasAll then
                table.insert(result, entity)
            end
        end
    end
    
    -- Cache do resultado
    entityGroups[cacheKey] = result
    return result
end

-- Registrar sistema
function ECS:addSystem(name, systemFunction, updateOrder)
    systems[name] = {
        func = systemFunction,
        order = updateOrder or 0,
        active = true
    }
    
    -- Reordenar sistemas
    local systemList = {}
    for sysName, sys in pairs(systems) do
        table.insert(systemList, {name = sysName, system = sys})
    end
    
    table.sort(systemList, function(a, b)
        local orderA = a.system.order or 0
        local orderB = b.system.order or 0
        return orderA < orderB
    end)
    
    systems.orderedList = systemList
end

-- Remover sistema
function ECS:removeSystem(name)
    systems[name] = nil
    
    -- Reconstruir lista ordenada
    if systems.orderedList then
        for i = #systems.orderedList, 1, -1 do
            if systems.orderedList[i].name == name then
                table.remove(systems.orderedList, i)
                break
            end
        end
    end
end

-- Ativar/desativar sistema
function ECS:setSystemActive(name, active)
    if systems[name] then
        systems[name].active = active
    end
end

-- Update todos os sistemas
function ECS:update(dt)
    if systems.orderedList then
        for _, sys in ipairs(systems.orderedList) do
            if sys.system.active then
                sys.system.func(dt, self)
            end
        end
    end
end

-- Limpar tudo
function ECS:clear()
    entityCounter = 0
    entities = {}
    components = {}
    systems = {}
    entityGroups = {}
end

-- Estatísticas para debug
function ECS:getStats()
    local entityCount = 0
    local componentCounts = {}
    
    for _, entity in pairs(entities) do
        if entity.active then
            entityCount = entityCount + 1
        end
    end
    
    for componentType, componentStorage in pairs(components) do
        componentCounts[componentType] = 0
        for _ in pairs(componentStorage) do
            componentCounts[componentType] = componentCounts[componentType] + 1
        end
    end
    
    return {
        entities = entityCount,
        components = componentCounts,
        systems = #(systems.orderedList or {}),
        cachedGroups = #entityGroups
    }
end

-- ==============================================
-- COMPONENTES PREDEFINIDOS PARA O JOGO
-- ==============================================

ECS.Components = {
    -- Posição e movimento
    Transform = "Transform",
    Velocity = "Velocity",
    
    -- Renderização
    Sprite = "Sprite",
    Animation = "Animation",
    
    -- Física/Colisão
    Collider = "Collider",
    RigidBody = "RigidBody",
    
    -- Gameplay
    Health = "Health",
    Combat = "Combat",
    
    -- Slime específico
    SlimeCore = "SlimeCore",
    Predation = "Predation",
    Analysis = "Analysis",
    Mimicry = "Mimicry",
    
    -- AI/Comportamento
    AI = "AI",
    PathFinding = "PathFinding",
    
    -- Itens/Loot
    Item = "Item",
    Lootable = "Lootable",
    
    -- Mundo
    Room = "Room",
    Spawner = "Spawner",
    
    -- Temporários
    Timer = "Timer",
    Lifetime = "Lifetime"
}

-- ==============================================
-- UTILITÁRIOS PARA CRIAR ENTIDADES COMPLEXAS
-- ==============================================

-- Criar slime player
function ECS:createSlime(x, y)
    local slime = self:createEntity()
    
    self:addComponent(slime, self.Components.Transform, {
        x = x or 0,
        y = y or 0,
        rotation = 0,
        scale = 1
    })
    
    self:addComponent(slime, self.Components.SlimeCore, {
        form = "base",
        essence = 0,
        maxHealth = 100,
        health = 100
    })
    
    self:addComponent(slime, self.Components.Velocity, {
        vx = 0,
        vy = 0,
        maxSpeed = 120
    })
    
    self:addComponent(slime, self.Components.Predation, {
        range = 32,
        channeling = false,
        channelTime = 0,
        stomach = {},
        capacity = 8
    })
    
    self:addComponent(slime, self.Components.Sprite, {
        texture = nil, -- Será gerado pelo sprite generator
        color = {0.0, 1.0, 0.0, 1}, -- Verde brilhante para ser mais visível
        size = 24 -- Aumentar tamanho
    })
    
    self:addComponent(slime, self.Components.Collider, {
        radius = 8,
        type = "circle"
    })
    
    return slime
end

-- Criar inimigo básico
function ECS:createEnemy(x, y, enemyType)
    local enemy = self:createEntity()
    
    self:addComponent(enemy, self.Components.Transform, {
        x = x or 0,
        y = y or 0,
        rotation = 0,
        scale = 1
    })
    
    self:addComponent(enemy, self.Components.Health, {
        current = 50,
        max = 50
    })
    
    self:addComponent(enemy, self.Components.AI, {
        type = enemyType or "wanderer",
        state = "idle",
        target = nil,
        alertRadius = 64,
        attackRadius = 16
    })
    
    self:addComponent(enemy, self.Components.Velocity, {
        vx = 0,
        vy = 0,
        maxSpeed = 60
    })
    
    self:addComponent(enemy, self.Components.Sprite, {
        texture = nil,
        color = {0.8, 0.2, 0.2, 1},
        size = 12
    })
    
    self:addComponent(enemy, self.Components.Collider, {
        radius = 6,
        type = "circle"
    })
    
    self:addComponent(enemy, self.Components.Lootable, {
        essence = math.random(5, 15),
        traits = {"basic_combat"},
        dropChance = 0.7
    })
    
    return enemy
end

-- Criar item/pickup
function ECS:createItem(x, y, itemType)
    local item = self:createEntity()
    
    self:addComponent(item, self.Components.Transform, {
        x = x or 0,
        y = y or 0,
        rotation = 0,
        scale = 0.8
    })
    
    self:addComponent(item, self.Components.Item, {
        type = itemType or "essence",
        value = math.random(1, 10),
        consumable = true
    })
    
    self:addComponent(item, self.Components.Sprite, {
        texture = nil,
        color = {0.9, 0.9, 0.2, 1},
        size = 8
    })
    
    self:addComponent(item, self.Components.Collider, {
        radius = 4,
        type = "circle",
        trigger = true
    })
    
    return item
end

return ECS 