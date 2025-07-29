-- rng.lua - Sistema de Números Aleatórios Determinísticos
-- Baseado em Xorshift para garantir reprodutibilidade com seeds

local RNG = {}

-- Estado interno do gerador
local state = {
    x = 123456789,
    y = 362436069, 
    z = 521288629,
    w = 88675123
}

-- Backup para restaurar estado
local savedState = nil

function RNG:setSeed(seed)
    seed = seed or os.time()
    
    -- Inicializar estado baseado na seed
    state.x = seed
    state.y = math.floor(seed / 2) + 1
    state.z = math.floor(seed / 3) + 2
    state.w = math.floor(seed / 4) + 3
    
    -- Executar algumas iterações para "misturar" o estado
    for i = 1, 10 do
        self:random()
    end
    
    print("RNG seed definida: " .. seed)
end

-- Funções de bit para Lua 5.1
local function lshift(x, by)
    return x * (2 ^ by)
end

local function rshift(x, by)
    return math.floor(x / (2 ^ by))
end

local function bxor(a, b)
    local r = 0
    for i = 0, 31 do
        local x = a / 2 + b / 2
        if x ~= math.floor(x) then
            r = r + 2^i
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return r
end

-- Xorshift 128 - gera número de 32 bits
function RNG:xorshift128()
    local t = state.x
    t = bxor(t, lshift(t, 11))
    t = bxor(t, rshift(t, 8))
    state.x = state.y
    state.y = state.z
    state.z = state.w
    state.w = bxor(state.w, bxor(rshift(state.w, 19), t))
    
    -- Garantir que seja positivo
    return math.abs(state.w)
end

-- Gera número float entre 0 e 1
function RNG:random()
    return self:xorshift128() / 2147483647 -- 2^31 - 1
end

-- Gera número inteiro entre min e max (inclusivo)
function RNG:randomInt(min, max)
    if not min then
        return self:xorshift128()
    end
    
    if not max then
        max = min
        min = 1
    end
    
    local range = max - min + 1
    return min + (self:xorshift128() % range)
end

-- Gera número float entre min e max
function RNG:randomFloat(min, max)
    min = min or 0
    max = max or 1
    return min + (max - min) * self:random()
end

-- Gera booleano com probabilidade p (0-1)
function RNG:randomBool(probability)
    probability = probability or 0.5
    return self:random() < probability
end

-- Escolhe elemento aleatório de uma lista
function RNG:choice(list)
    if #list == 0 then return nil end
    local index = self:randomInt(1, #list)
    return list[index], index
end

-- Embaralha uma lista (modifica in-place)
function RNG:shuffle(list)
    for i = #list, 2, -1 do
        local j = self:randomInt(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

-- Cria nova lista embaralhada (não modifica original)
function RNG:shuffled(list)
    local newList = {}
    for i, v in ipairs(list) do
        newList[i] = v
    end
    return self:shuffle(newList)
end

-- Escolha ponderada - lista de {item, peso}
function RNG:weightedChoice(weightedList)
    if #weightedList == 0 then return nil end
    
    local totalWeight = 0
    for _, item in ipairs(weightedList) do
        totalWeight = totalWeight + item[2]
    end
    
    local target = self:randomFloat(0, totalWeight)
    local current = 0
    
    for _, item in ipairs(weightedList) do
        current = current + item[2]
        if current >= target then
            return item[1]
        end
    end
    
    -- Fallback (não deveria acontecer)
    return weightedList[#weightedList][1]
end

-- Gera ponto em círculo
function RNG:randomInCircle(radius)
    radius = radius or 1
    local angle = self:randomFloat(0, 2 * math.pi)
    local r = radius * math.sqrt(self:random())
    return r * math.cos(angle), r * math.sin(angle)
end

-- Gera ponto em retângulo
function RNG:randomInRect(x, y, width, height)
    return x + self:randomFloat(0, width), y + self:randomFloat(0, height)
end

-- Ruído baseado em coordenadas (determinístico)
function RNG:noise2D(x, y, scale)
    scale = scale or 1
    x = x * scale
    y = y * scale
    
    -- Hash das coordenadas
    local hash = math.floor(x) * 374761393 + math.floor(y) * 668265263
    hash = bxor(hash, rshift(hash, 13))
    hash = hash * 1274126177
    hash = bxor(hash, rshift(hash, 16))
    
    -- Normalizar para [0,1]
    return (math.abs(hash) % 1000000) / 1000000
end

-- Salvar estado atual
function RNG:saveState()
    savedState = {
        x = state.x,
        y = state.y,
        z = state.z,
        w = state.w
    }
end

-- Restaurar estado salvo
function RNG:restoreState()
    if savedState then
        state.x = savedState.x
        state.y = savedState.y
        state.z = savedState.z
        state.w = savedState.w
    end
end

-- Obter estado atual (para debug)
function RNG:getState()
    return {
        x = state.x,
        y = state.y,
        z = state.z,
        w = state.w
    }
end

-- Utilitários para game design

-- Chance crítica com streak protection
function RNG:criticalHit(baseChance, streakCount)
    local adjustedChance = baseChance + (streakCount * 0.1) -- +10% por miss consecutivo
    return self:randomBool(adjustedChance)
end

-- Drop rate com bad luck protection
function RNG:dropRoll(baseRate, attempts)
    local adjustedRate = baseRate * (1 + attempts * 0.05) -- +5% por tentativa
    return self:randomBool(math.min(adjustedRate, 0.95)) -- Cap em 95%
end

-- Distribuição gaussiana aproximada (Box-Muller)
function RNG:gaussian(mean, stddev)
    mean = mean or 0
    stddev = stddev or 1
    
    if not self.gaussianNext then
        local u1 = self:random()
        local u2 = self:random()
        local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
        local z1 = math.sqrt(-2 * math.log(u1)) * math.sin(2 * math.pi * u2)
        
        self.gaussianNext = z1
        return mean + z0 * stddev
    else
        local result = self.gaussianNext
        self.gaussianNext = nil
        return mean + result * stddev
    end
end

-- Variação de stat com limites
function RNG:statVariation(baseStat, variationPercent, minValue, maxValue)
    variationPercent = variationPercent or 0.2
    local variation = self:gaussian(0, baseStat * variationPercent)
    local result = baseStat + variation
    
    if minValue then result = math.max(result, minValue) end
    if maxValue then result = math.min(result, maxValue) end
    
    return result
end

return RNG 