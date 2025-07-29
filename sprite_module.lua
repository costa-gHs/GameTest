-- sprite_module.lua - Versão simplificada do gerador de sprites para uso como módulo

local SpriteModule = {}

-- Funções utilitárias
local function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Paletas de cores
local PALETTES = {
    NES = {
        {0.2, 0.2, 0.2, 1}, -- Preto
        {0.4, 0.4, 0.4, 1}, -- Cinza escuro
        {0.6, 0.6, 0.6, 1}, -- Cinza médio
        {0.8, 0.8, 0.8, 1}, -- Cinza claro
        {1.0, 1.0, 1.0, 1}, -- Branco
        {0.8, 0.2, 0.2, 1}, -- Vermelho
        {0.2, 0.8, 0.2, 1}, -- Verde
        {0.2, 0.2, 0.8, 1}  -- Azul
    }
}

-- Gerar sprite simples
function SpriteModule:generate(settings)
    settings = settings or {}
    local size = settings.size or 16
    local paletteType = settings.paletteType or "NES"
    local complexity = settings.complexity or 50
    local symmetry = settings.symmetry or "vertical"
    
    local palette = PALETTES[paletteType] or PALETTES.NES
    local sprite = {}
    
    -- Inicializar sprite vazio
    for y = 1, size do
        sprite[y] = {}
        for x = 1, size do
            sprite[y][x] = {0, 0, 0, 0} -- Transparente
        end
    end
    
    -- Gerar forma básica
    local centerX = math.floor(size / 2)
    local centerY = math.floor(size / 2)
    local radius = math.floor(size / 3)
    
    -- Preencher círculo básico
    for y = 1, size do
        for x = 1, size do
            local dx = x - centerX
            local dy = y - centerY
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance <= radius then
                local colorIndex = math.random(1, #palette)
                sprite[y][x] = palette[colorIndex]
            end
        end
    end
    
    -- Adicionar detalhes baseados na complexidade
    if complexity > 30 then
        -- Adicionar olhos
        local eyeY = centerY - 2
        local eyeX1 = centerX - 2
        local eyeX2 = centerX + 2
        
        if eyeY > 0 and eyeY <= size and eyeX1 > 0 and eyeX1 <= size then
            sprite[eyeY][eyeX1] = {0, 0, 0, 1} -- Olho preto
        end
        if eyeY > 0 and eyeY <= size and eyeX2 > 0 and eyeX2 <= size then
            sprite[eyeY][eyeX2] = {0, 0, 0, 1} -- Olho preto
        end
    end
    
    return sprite
end

return SpriteModule 