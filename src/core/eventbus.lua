-- eventbus.lua - Sistema de Eventos Global
-- Permite comunicação desacoplada entre módulos

local EventBus = {}

-- Lista de listeners por evento
local listeners = {}
-- Fila de eventos para processar
local eventQueue = {}
-- Histórico de eventos (para debug)
local eventHistory = {}
local maxHistory = 100

function EventBus:on(eventName, callback, priority)
    priority = priority or 0
    
    if not listeners[eventName] then
        listeners[eventName] = {}
    end
    
    table.insert(listeners[eventName], {
        callback = callback,
        priority = priority
    })
    
    -- Ordenar por prioridade (maior prioridade primeiro)
    table.sort(listeners[eventName], function(a, b)
        return a.priority > b.priority
    end)
end

function EventBus:off(eventName, callback)
    if not listeners[eventName] then return end
    
    for i = #listeners[eventName], 1, -1 do
        if listeners[eventName][i].callback == callback then
            table.remove(listeners[eventName], i)
            break
        end
    end
end

function EventBus:emit(eventName, data)
    local event = {
        name = eventName,
        data = data or {},
        timestamp = love.timer.getTime()
    }
    
    table.insert(eventQueue, event)
    
    -- Adicionar ao histórico
    table.insert(eventHistory, event)
    if #eventHistory > maxHistory then
        table.remove(eventHistory, 1)
    end
end

function EventBus:emitImmediate(eventName, data)
    local event = {
        name = eventName,
        data = data or {},
        timestamp = love.timer.getTime()
    }
    
    self:processEvent(event)
end

function EventBus:processEvent(event)
    if listeners[event.name] then
        for _, listener in ipairs(listeners[event.name]) do
            local success, error = pcall(listener.callback, event.data)
            if not success then
                print("Erro no evento '" .. event.name .. "': " .. tostring(error))
            end
        end
    end
end

function EventBus:update(dt)
    -- Processar todos os eventos da fila
    while #eventQueue > 0 do
        local event = table.remove(eventQueue, 1)
        self:processEvent(event)
    end
end

function EventBus:clear()
    eventQueue = {}
    listeners = {}
end

function EventBus:getHistory()
    return eventHistory
end

function EventBus:getListeners(eventName)
    return listeners[eventName] or {}
end

-- Eventos predefinidos do sistema
local SystemEvents = {
    -- App lifecycle
    APP_INITIALIZED = "app:initialized",
    STATE_CHANGED = "state:changed",
    
    -- Run lifecycle  
    RUN_STARTED = "run:started",
    RUN_ENDED = "run:ended",
    
    -- Slime events
    SLIME_MOVED = "slime:moved",
    SLIME_DAMAGED = "slime:damaged",
    SLIME_HEALED = "slime:healed",
    SLIME_DIED = "slime:died",
    
    -- Predation system
    PREDATION_STARTED = "predation:started",
    PREDATION_COMPLETED = "predation:completed",
    PREDATION_FAILED = "predation:failed",
    
    -- Analysis system
    ANALYSIS_STARTED = "analysis:started",
    ANALYSIS_COMPLETED = "analysis:completed",
    TRAIT_DISCOVERED = "trait:discovered",
    SKILL_UNLOCKED = "skill:unlocked",
    
    -- Combat
    ENEMY_SPAWNED = "enemy:spawned",
    ENEMY_DIED = "enemy:died",
    BOSS_ENCOUNTERED = "boss:encountered",
    BOSS_DEFEATED = "boss:defeated",
    
    -- World
    ROOM_ENTERED = "room:entered",
    BIOME_CHANGED = "biome:changed",
    ITEM_FOUND = "item:found",
    
    -- Sage advisor
    SAGE_ADVICE = "sage:advice",
    SAGE_EVOLVED = "sage:evolved",
    
    -- Meta progression
    TECH_UNLOCKED = "tech:unlocked",
    CITY_UPGRADED = "city:upgraded",
    
    -- UI
    UI_OPENED = "ui:opened",
    UI_CLOSED = "ui:closed"
}

EventBus.Events = SystemEvents

return EventBus 