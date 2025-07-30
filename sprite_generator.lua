-- sprite_generator.lua - Gerador de Sprites Original
-- Este é o gerador procedural de sprites que estava originalmente no main.lua

-- improved_main.lua - Gerador de Sprites Pixel Art com melhorias de estilo 8/16‑bit
-- Este arquivo é uma versão aprimorada do gerador original. Ele inclui ajustes de cor,
-- silhueta, contorno seletivo (sel‑out), cluster shading, destaques diagonais em armas,
-- parâmetros adicionais de anatomia e iluminação e um sistema de animação com respiração
-- e variação de cor.  Algumas funcionalidades listadas no enunciado são complexas e
-- exigiriam um projeto muito maior; aqui implementamos as principais ideias para
-- demonstrar como elas podem ser incorporadas.

-- Módulos necessários
local SpriteGenerator = {}
local AnimationSystem = {}
local UIManager = {}
local PaletteManager = {}
local ExportManager = {}
local PresetManager = {}
local Utils = {}

-- Variáveis globais
local generator
local animation
local ui
local palette
local export
local preset

local currentSprite = nil
local spriteHistory = {}
local maxHistory = 8
local settings = {}

-- Cores do tema da interface
local COLORS = {
    bg = {0.05, 0.05, 0.08},
    panel = {0.1, 0.1, 0.12},
    panelLight = {0.15, 0.15, 0.18},
    accent = {0.3, 0.7, 0.9},
    accentDark = {0.2, 0.5, 0.7},
    text = {0.9, 0.9, 0.9},
    textDim = {0.6, 0.6, 0.6},
    success = {0.3, 0.8, 0.3},
    warning = {0.9, 0.7, 0.2},
    error = {0.9, 0.3, 0.3},
    grid = {0.2, 0.2, 0.25}
}

-- Configurações padrão – foram adicionados novos parâmetros para silhueta,
-- proporção do corpo e direção da luz.  O parâmetro `visualSeed` controla variações
-- de cor e detalhe, enquanto `structureSeed` controla a estrutura (silhueta).
local DEFAULT_SETTINGS = {
    spriteType = "character",
    size = 16,
    paletteType = "NES",
    complexity = 50,
    symmetry = "vertical",
    roughness = 30,
    colorCount = 6,
    -- seeds separados para permitir explorar variações visuais mantendo a silhueta
    visualSeed = os.time(),
    structureSeed = os.time(),
    anatomyScale = 50,
    class = "warrior",
    detailLevel = 50,
    outline = true,
    frameCount = 4,
    animationSpeed = 0.1,
    style = "organic",
    -- parâmetros adicionais
    bodyRatio = 4,          -- proporção corpo:cabeça (maior => cabeça menor)
    limbLength = 50,        -- comprimento dos membros (0‑100)
    silhouetteStyle = "heroic", -- estilo de silhueta (heroic, chibi, realistic)
    lightDir = "top-left", -- direção de luz para sel‑out
    weaponTrails = false    -- ativa trilhas de arma
}

-- ==============================================
-- UTILS MODULE
-- Funções utilitárias com novas operações para iluminação
-- ==============================================
function Utils.clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.noise(x, y, seed)
    -- Simple Perlin‑like noise function based on permutation table. Para o
    -- propósito deste gerador, mantém a implementação original.
    local function fade(t) return t * t * t * (t * (t * 6 - 15) + 10) end
    local function grad(hash, x, y)
        local h = hash % 4
        local u = h < 2 and x or y
        local v = h < 2 and y or x
        return ((h % 2) == 0 and u or -u) + ((h == 1 or h == 2) and -v or v)
    end
    seed = seed or 0
    x = x + seed * 0.1
    y = y + seed * 0.1
    local xi = math.floor(x) % 256
    local yi = math.floor(y) % 256
    local xf = x - math.floor(x)
    local yf = y - math.floor(y)
    local u = fade(xf)
    local v = fade(yf)
    local p = {}
    for i = 0, 255 do p[i] = i end
    math.randomseed(seed)
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        p[i], p[j] = p[j], p[i]
    end
    local function perm(val) return p[val % 256] end
    local aa = perm(perm(xi) + yi)
    local ab = perm(perm(xi) + yi + 1)
    local ba = perm(perm(xi + 1) + yi)
    local bb = perm(perm(xi + 1) + yi + 1)
    local x1 = Utils.lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u)
    local x2 = Utils.lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u)
    return Utils.lerp(x1, x2, v)
end

function Utils.deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = Utils.deepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

function Utils.drawRoundedRect(x, y, w, h, radius)
    love.graphics.rectangle("fill", x + radius, y, w - radius * 2, h)
    love.graphics.rectangle("fill", x, y + radius, w, h - radius * 2)
    love.graphics.circle("fill", x + radius, y + radius, radius)
    love.graphics.circle("fill", x + w - radius, y + radius, radius)
    love.graphics.circle("fill", x + radius, y + h - radius, radius)
    love.graphics.circle("fill", x + w - radius, y + h - radius, radius)
end

-- Calcula brilho de uma cor (média de r,g,b)
function Utils.brightness(color)
    return (color[1] + color[2] + color[3]) / 3
end

-- Ajusta a luminosidade de uma cor; factor > 1 clareia, <1 escurece
function Utils.adjustColor(color, factor)
    return {
        Utils.clamp(color[1] * factor, 0, 1),
        Utils.clamp(color[2] * factor, 0, 1),
        Utils.clamp(color[3] * factor, 0, 1),
        color[4]
    }
end

-- Retorna a cor mais escura entre as do sprite (ignorando pixels transparentes)
function Utils.getDarkestColor(sprite)
    local darkest = {1, 1, 1, 1}
    local minBright = 10
    for y = 1, #sprite do
        for x = 1, #sprite[y] do
            local pix = sprite[y][x]
            if pix[4] > 0 then
                local b = Utils.brightness(pix)
                if b < minBright then
                    minBright = b
                    darkest = pix
                end
            end
        end
    end
    return darkest
end

-- ==============================================
-- PALETTE MANAGER MODULE
-- Foram adicionadas variações de luminosidade para criar subtons mais ricos.
-- ==============================================
function PaletteManager:new()
    local pm = {}
    setmetatable(pm, { __index = self })
    pm.palettes = {
        NES = {
            {0.0, 0.0, 0.0},      -- Black
            {0.19, 0.19, 0.19},   -- Dark Gray
            {0.5, 0.5, 0.5},      -- Gray
            {1.0, 1.0, 1.0},      -- White
            {0.74, 0.19, 0.19},   -- Red
            {0.94, 0.38, 0.38},   -- Light Red
            {0.19, 0.38, 0.74},   -- Blue
            {0.38, 0.56, 0.94},   -- Light Blue
            {0.19, 0.74, 0.19},   -- Green
            {0.38, 0.94, 0.38},   -- Light Green
            {0.74, 0.74, 0.19},   -- Yellow
            {0.94, 0.94, 0.38},   -- Light Yellow
            {0.74, 0.38, 0.19},   -- Brown
            {0.94, 0.56, 0.38},   -- Light Brown
            {0.74, 0.19, 0.74},   -- Purple
            {0.94, 0.38, 0.94}    -- Light Purple
        },
        GameBoy = {
            {0.06, 0.22, 0.06},   -- Darkest Green
            {0.19, 0.38, 0.19},   -- Dark Green
            {0.55, 0.67, 0.06},   -- Light Green
            {0.74, 0.89, 0.42}    -- Lightest Green
        },
        C64 = {
            {0.0, 0.0, 0.0},      -- Black
            {1.0, 1.0, 1.0},      -- White
            {0.53, 0.0, 0.0},     -- Red
            {0.67, 1.0, 0.93},    -- Cyan
            {0.8, 0.27, 0.8},     -- Purple
            {0.0, 0.8, 0.33},     -- Green
            {0.0, 0.0, 0.67},     -- Blue
            {1.0, 1.0, 0.47},     -- Yellow
            {0.8, 0.47, 0.0},     -- Orange
            {0.47, 0.3, 0.0},     -- Brown
            {1.0, 0.47, 0.47},    -- Light Red
            {0.33, 0.33, 0.33},   -- Dark Gray
            {0.47, 0.47, 0.47},   -- Medium Gray
            {0.67, 1.0, 0.4},     -- Light Green
            {0.0, 0.53, 1.0},     -- Light Blue
            {0.73, 0.73, 0.73}    -- Light Gray
        }
    }
    pm.currentPalette = "NES"
    pm.customPalette = {}
    return pm
end

function PaletteManager:getPalette()
    return self.palettes[self.currentPalette] or self.palettes.NES
end

function PaletteManager:getColor(index)
    local palette = self:getPalette()
    return palette[math.max(1, math.min(#palette, index))]
end

-- Retorna uma cor aleatória com variação de brilho para criar sub‑tons.
function PaletteManager:getRandomColor(settings)
    local palette = self:getPalette()
    local maxColors = math.min(settings.colorCount, #palette)
    local index = math.random(1, maxColors)
    local base = palette[index]
    -- Varia o brilho em ±20 % com ruído. Isso melhora percepção de volume.
    local variation = (Utils.noise(index, settings.visualSeed or 0, settings.visualSeed or 0) * 0.4)
    return {
        Utils.clamp(base[1] + base[1] * variation, 0, 1),
        Utils.clamp(base[2] + base[2] * variation, 0, 1),
        Utils.clamp(base[3] + base[3] * variation, 0, 1),
        1
    }
end

-- ==============================================
-- SPRITE GENERATOR MODULE
-- Incorporou parâmetros extras para silhueta e novas técnicas (cluster shading,
-- destaque diagonal, contorno seletivo).
-- ==============================================
function SpriteGenerator:new()
    local sg = {}
    setmetatable(sg, { __index = self })
    sg.generators = {
        character = function(self, s) return self:generateCharacter(s) end,
        weapon = function(self, s) return self:generateWeapon(s) end,
        item = function(self, s) return self:generateItem(s) end,
        tile = function(self, s) return self:generateTile(s) end
    }
    return sg
end

function SpriteGenerator:generate(settings)
    local generator = self.generators[settings.spriteType] or self.generators.character
    return generator(self, settings)
end

function SpriteGenerator:createEmptySprite(size)
    local sprite = {}
    for y = 1, size do
        sprite[y] = {}
        for x = 1, size do
            sprite[y][x] = {0, 0, 0, 0}
        end
    end
    return sprite
end

function SpriteGenerator:applySymmetry(sprite, symmetry)
    local size = #sprite
    if symmetry == "vertical" or symmetry == "both" then
        for y = 1, size do
            for x = 1, math.floor(size / 2) do
                sprite[y][size - x + 1] = Utils.deepCopy(sprite[y][x])
            end
        end
    end
    if symmetry == "horizontal" or symmetry == "both" then
        for y = 1, math.floor(size / 2) do
            for x = 1, size do
                sprite[size - y + 1][x] = Utils.deepCopy(sprite[y][x])
            end
        end
    end
    return sprite
end

-- Contorno seletivo: utiliza a direção de luz definida em settings.lightDir.
-- Usa a cor de sombra do sprite para regiões de sombra e clareia ou remove o
-- contorno em regiões iluminadas.
function SpriteGenerator:addOutline(sprite, settings)
    local size = #sprite
    local outlined = self:createEmptySprite(size)
    -- Copiar sprite original
    for y = 1, size do
        for x = 1, size do
            outlined[y][x] = Utils.deepCopy(sprite[y][x])
        end
    end
    -- Determinar cor mais escura do sprite (para contorno)
    local darkest = Utils.getDarkestColor(sprite)
    -- Determinar vetor de luz
    local lightVec = {0, -1} -- padrão top
    if settings.lightDir == "top-left" then lightVec = {-1, -1}
    elseif settings.lightDir == "top-right" then lightVec = {1, -1}
    elseif settings.lightDir == "front" then lightVec = {0, -1} end
    -- Adicionar contorno
    for y = 1, size do
        for x = 1, size do
            if sprite[y][x][4] > 0 then
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        if dx ~= 0 or dy ~= 0 then
                            local ny, nx = y + dy, x + dx
                            if ny >= 1 and ny <= size and nx >= 1 and nx <= size then
                                if sprite[ny][nx][4] == 0 then
                                    -- calcular direção do pixel em relação ao centro
                                    local cx, cy = size / 2, size / 2
                                    local dirX, dirY = x - cx, y - cy
                                    local dot = dirX * lightVec[1] + dirY * lightVec[2]
                                    if dot > 0 then
                                        -- área iluminada: clarear contorno ou remover
                                        -- usar cor original levemente mais clara
                                        outlined[ny][nx] = Utils.adjustColor(sprite[y][x], 1.3)
                                    else
                                        -- área em sombra: usar cor de sombra
                                        outlined[ny][nx] = {darkest[1], darkest[2], darkest[3], 1}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return outlined
end

-- Aplica cluster shading e dithering após gerar o sprite. Com base na
-- complexidade e no nível de detalhe, agrupa pixels em blocos de 2×2 e
-- aplica ruído para variação de brilho.
function SpriteGenerator:applyClusterShading(sprite, settings)
    local size = #sprite
    local blockSize = 2
    for y = 1, size, blockSize do
        for x = 1, size, blockSize do
            local noiseVal = Utils.noise(x * 0.3, y * 0.3, settings.visualSeed)
            if noiseVal > 0.2 and settings.detailLevel > 30 then
                -- clarear bloco
                for by = y, math.min(y + blockSize - 1, size) do
                    for bx = x, math.min(x + blockSize - 1, size) do
                        local pix = sprite[by][bx]
                        if pix[4] > 0 then
                            sprite[by][bx] = Utils.adjustColor(pix, 1.1)
                        end
                    end
                end
            elseif noiseVal < -0.2 and settings.detailLevel > 30 then
                -- escurecer bloco
                for by = y, math.min(y + blockSize - 1, size) do
                    for bx = x, math.min(x + blockSize - 1, size) do
                        local pix = sprite[by][bx]
                        if pix[4] > 0 then
                            sprite[by][bx] = Utils.adjustColor(pix, 0.9)
                        end
                    end
                end
            end
        end
    end
    return sprite
end

-- Adiciona um destaque diagonal em lâminas de espada para simular reflexo.
function SpriteGenerator:addDiagonalHighlight(sprite)
    local size = #sprite
    for y = 1, size do
        for x = 1, size do
            local pix = sprite[y][x]
            if pix[4] > 0 then
                -- adiciona um destaque diagonal a cada 3 pixels
                if (x + y) % 3 == 0 then
                    sprite[y][x] = Utils.adjustColor(pix, 1.3)
                end
            end
        end
    end
    return sprite
end

function SpriteGenerator:generateCharacter(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.structureSeed)
    -- Definições de classe influenciam proporções básicas
    local structures = {
        warrior = { head = 0.3, body = 0.4, shoulders = 0.5, legs = 0.3 },
        mage    = { head = 0.35, body = 0.3, shoulders = 0.35, legs = 0.2 },
        archer  = { head = 0.28, body = 0.35, shoulders = 0.4, legs = 0.25 }
    }
    local struct = structures[settings.class] or structures.warrior
    -- Ajustar proporções conforme bodyRatio: quanto maior a razão, menor a cabeça
    local ratio = settings.bodyRatio or 4
    -- mapa estilo de silhueta
    if settings.silhouetteStyle == "chibi" then ratio = 2
    elseif settings.silhouetteStyle == "realistic" then ratio = 6 end
    local headFactor = 1 / (ratio + 1)
    local bodyFactor = 1 - headFactor
    local headSize = math.floor(size * headFactor * struct.head / 0.3)
    -- gerar cabeça
    local headCenterX = math.floor(size / 2)
    local headTop = math.floor(size * 0.1)
    for y = headTop, headTop + headSize do
        for x = headCenterX - math.floor(headSize/2), headCenterX + math.floor(headSize/2) do
            if x > 0 and x <= size and y > 0 and y <= size then
                local dist = math.sqrt((x - headCenterX)^2 + (y - (headTop + headSize/2))^2)
                if dist < headSize/2 then
                    -- usar visualSeed para cor
                    local c = palette:getRandomColor(settings)
                    sprite[y][x] = {c[1], c[2], c[3], 1}
                end
            end
        end
    end
    -- gerar corpo
    local bodyHeight = math.floor(size * bodyFactor * struct.body / 0.4)
    local bodyStart = headTop + headSize
    local bodyWidth = math.floor(size * struct.body * (settings.anatomyScale/50) )
    for y = bodyStart, math.min(bodyStart + bodyHeight, size) do
        local widthAtY = bodyWidth * (1 - (y - bodyStart) / math.max(bodyHeight,1) * 0.2)
        for x = headCenterX - math.floor(widthAtY/2), headCenterX + math.floor(widthAtY/2) do
            if x > 0 and x <= size and y > 0 and y <= size then
                local noiseVal = Utils.noise(x * 0.2, y * 0.2, settings.visualSeed + 100)
                if noiseVal > -0.4 then
                    local c = palette:getRandomColor(settings)
                    sprite[y][x] = {c[1], c[2], c[3], 1}
                end
            end
        end
    end
    -- gerar braços (comprimento proporcional a limbLength)
    local armStart = bodyStart + math.floor(bodyHeight * 0.2)
    local armLength = math.floor(size * (settings.limbLength/100) * 0.5)
    local shoulderWidth = math.floor(size * struct.shoulders * (settings.anatomyScale/50))
    -- braço esquerdo
    for i = 0, armLength do
        local x = headCenterX - shoulderWidth/2 - i/2
        local y = armStart + i
        if x > 0 and x <= size and y > 0 and y <= size then
            local c = palette:getRandomColor(settings)
            sprite[math.floor(y)][math.floor(x)] = {c[1], c[2], c[3], 1}
        end
    end
    -- gerar pernas
    local legStart = bodyStart + bodyHeight
    local legHeight = size - legStart - 1
    local legSpread = math.floor(size * struct.legs * (settings.limbLength/100))
    for i = 0, legHeight do
        local x = headCenterX - legSpread/2
        local y = legStart + i
        if x > 0 and x <= size and y > 0 and y <= size then
            local c = palette:getRandomColor(settings)
            sprite[math.floor(y)][math.floor(x)] = {c[1], c[2], c[3], 1}
        end
    end
    -- aplicar simetria
    sprite = self:applySymmetry(sprite, settings.symmetry)
    -- contorno seletivo
    if settings.outline then sprite = self:addOutline(sprite, settings) end
    -- cluster shading / dithering
    sprite = self:applyClusterShading(sprite, settings)
    return sprite
end

function SpriteGenerator:generateWeapon(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.structureSeed)
    local weaponTypes = {
        sword = function()
            local bladeLength = math.floor(size * 0.7)
            local bladeWidth = math.floor(size * 0.15)
            local handleLength = math.floor(size * 0.3)
            for y = 1, bladeLength do
                local width = bladeWidth * (1 - y / bladeLength * 0.5)
                for x = size/2 - width/2, size/2 + width/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local c = palette:getRandomColor(settings)
                        sprite[math.floor(y)][math.floor(x)] = {c[1], c[2], c[3], 1}
                    end
                end
            end
            for y = bladeLength, bladeLength + handleLength do
                for x = size/2 - 1, size/2 + 1 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.4, 0.2, 0.1, 1}
                    end
                end
            end
            local guardY = bladeLength
            for x = size/2 - 3, size/2 + 3 do
                if x > 0 and x <= size and guardY > 0 and guardY <= size then
                    sprite[guardY][math.floor(x)] = {0.6, 0.6, 0.7, 1}
                end
            end
        end,
        axe = function()
            local headSize = math.floor(size * 0.4)
            local handleLength = math.floor(size * 0.8)
            for y = 1, handleLength do
                local x = size/2
                if x > 0 and x <= size and y > 0 and y <= size then
                    sprite[math.floor(y)][math.floor(x)] = {0.4, 0.2, 0.1, 1}
                end
            end
            for y = 1, headSize do
                for x = size/2, size/2 + headSize/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local dist = math.abs(y - headSize/2)
                        if x - size/2 < headSize/2 - dist then
                            sprite[math.floor(y)][math.floor(x)] = {0.7, 0.7, 0.8, 1}
                        end
                    end
                end
            end
        end,
        staff = function()
            local length = math.floor(size * 0.9)
            local orbSize = math.floor(size * 0.2)
            for y = orbSize, length do
                local x = size/2
                if x > 0 and x <= size and y > 0 and y <= size then
                    sprite[math.floor(y)][math.floor(x)] = {0.5, 0.3, 0.2, 1}
                end
            end
            local orbCenter = orbSize/2
            for y = 1, orbSize do
                for x = size/2 - orbSize/2, size/2 + orbSize/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local dist = math.sqrt((x - size/2)^2 + (y - orbCenter)^2)
                        if dist < orbSize/2 then
                            local c = palette:getRandomColor(settings)
                            -- orb com brilho suave
                            local bfactor = 1 + (0.3 * (orbSize/2 - dist) / (orbSize/2))
                            sprite[math.floor(y)][math.floor(x)] = {Utils.clamp(c[1]*bfactor,0,1), Utils.clamp(c[2]*bfactor,0,1), Utils.clamp(c[3]*bfactor,0,1), 1}
                        end
                    end
                end
            end
        end
    }
    local types = {"sword", "axe", "staff"}
    local selectedType = types[(settings.structureSeed % #types) + 1]
    weaponTypes[selectedType]()
    -- efeitos de complexidade – glow
    if settings.complexity > 70 then
        for y = 1, size do
            for x = 1, size do
                if sprite[y][x][4] > 0 then
                    local noiseVal = Utils.noise(x * 0.5, y * 0.5, settings.visualSeed)
                    if noiseVal > 0.3 then
                        sprite[y][x] = Utils.adjustColor(sprite[y][x], 1.2)
                    end
                end
            end
        end
    end
    sprite = self:applySymmetry(sprite, settings.symmetry)
    if settings.outline then sprite = self:addOutline(sprite, settings) end
    if selectedType == "sword" then sprite = self:addDiagonalHighlight(sprite) end
    return sprite
end

function SpriteGenerator:generateItem(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.structureSeed)
    local itemTypes = {
        potion = function()
            local bottleHeight = math.floor(size * 0.7)
            local bottleWidth = math.floor(size * 0.4)
            local neckHeight = math.floor(size * 0.2)
            for y = size - bottleHeight, size do
                local width = bottleWidth * (0.8 + 0.2 * math.sin((y - size + bottleHeight) / bottleHeight * math.pi))
                for x = size/2 - width/2, size/2 + width/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local c = palette:getRandomColor(settings)
                        sprite[math.floor(y)][math.floor(x)] = {c[1] * 0.8, c[2] * 0.8, c[3], 0.9}
                    end
                end
            end
            for y = size - bottleHeight - neckHeight, size - bottleHeight do
                for x = size/2 - 1, size/2 + 1 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.8, 0.8, 0.8, 1}
                    end
                end
            end
            local corkY = size - bottleHeight - neckHeight
            for x = size/2 - 2, size/2 + 2 do
                if x > 0 and x <= size and corkY > 0 and corkY <= size then
                    sprite[corkY][math.floor(x)] = {0.6, 0.4, 0.3, 1}
                end
            end
        end,
        gem = function()
            local gemSize = math.floor(size * 0.6)
            local centerX, centerY = size/2, size/2
            for y = centerY - gemSize/2, centerY + gemSize/2 do
                for x = centerX - gemSize/2, centerX + gemSize/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local dx = x - centerX
                        local dy = y - centerY
                        local dist = math.sqrt(dx*dx + dy*dy)
                        if dist < gemSize/2 then
                            local angle = math.atan2(dy, dx)
                            local facet = math.floor((angle + math.pi) / (math.pi * 2) * 6)
                            local c = palette:getRandomColor(settings)
                            local brightness = 0.7 + 0.3 * (facet % 2)
                            sprite[math.floor(y)][math.floor(x)] = {c[1] * brightness, c[2] * brightness, c[3] * brightness, 1}
                        end
                    end
                end
            end
        end,
        chest = function()
            local chestHeight = math.floor(size * 0.5)
            local chestWidth = math.floor(size * 0.7)
            local startY = size - chestHeight
            for y = startY, size do
                for x = size/2 - chestWidth/2, size/2 + chestWidth/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.5, 0.3, 0.1, 1}
                    end
                end
            end
            for y = startY - 2, startY do
                for x = size/2 - chestWidth/2, size/2 + chestWidth/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.6, 0.4, 0.2, 1}
                    end
                end
            end
            local lockX = size/2
            local lockY = startY + chestHeight/2
            if lockX > 0 and lockX <= size and lockY > 0 and lockY <= size then
                sprite[math.floor(lockY)][math.floor(lockX)] = {0.8, 0.7, 0.1, 1}
            end
        end
    }
    local types = {"potion", "gem", "chest"}
    local selectedType = types[(settings.structureSeed % #types) + 1]
    itemTypes[selectedType]()
    if settings.outline then sprite = self:addOutline(sprite, settings) end
    return sprite
end

function SpriteGenerator:generateTile(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.structureSeed)
    local baseColor = palette:getRandomColor(settings)
    for y = 1, size do
        for x = 1, size do
            sprite[y][x] = {baseColor[1], baseColor[2], baseColor[3], 1}
        end
    end
    -- noise para textura não linear (blob pattern)
    local noiseScale = 0.1 + (settings.complexity / 100) * 0.4
    for y = 1, size do
        for x = 1, size do
            local n = Utils.noise(x * noiseScale, y * noiseScale, settings.visualSeed)
            if n > 0.6 then
                local c2 = palette:getRandomColor(settings)
                sprite[y][x] = { Utils.lerp(baseColor[1], c2[1], 0.3), Utils.lerp(baseColor[2], c2[2], 0.3), Utils.lerp(baseColor[3], c2[3], 0.3), 1 }
            elseif n < -0.6 then
                sprite[y][x] = { baseColor[1] * 0.8, baseColor[2] * 0.8, baseColor[3] * 0.8, 1 }
            end
        end
    end
    if settings.style == "geometric" then
        local gridSize = math.floor(size / 4)
        for y = 1, size do
            for x = 1, size do
                if x % gridSize == 0 or y % gridSize == 0 then
                    sprite[y][x] = { sprite[y][x][1]*0.7, sprite[y][x][2]*0.7, sprite[y][x][3]*0.7, 1 }
                end
                -- quebra de grade: desloca 10 % das células 1 pixel
                if math.random() < 0.1 then
                    local nx = math.min(size, x + 1)
                    sprite[y][x] = sprite[y][nx]
                end
            end
        end
    end
    return sprite
end

function SpriteGenerator:applyBlockyStyle(sprite, settings)
    -- mantido igual ao original
    local size = #sprite
    local blockSize = math.max(2, math.floor(size / 8))
    for y = 1, size, blockSize do
        for x = 1, size, blockSize do
            local r,g,b,a = 0,0,0,0
            local count = 0
            for by = y, math.min(y + blockSize - 1, size) do
                for bx = x, math.min(x + blockSize - 1, size) do
                    if sprite[by][bx][4] > 0 then
                        r = r + sprite[by][bx][1]
                        g = g + sprite[by][bx][2]
                        b = b + sprite[by][bx][3]
                        a = a + sprite[by][bx][4]
                        count = count + 1
                    end
                end
            end
            if count > 0 then
                r = r / count
                g = g / count
                b = b / count
                a = a / count
                for by = y, math.min(y + blockSize - 1, size) do
                    for bx = x, math.min(x + blockSize - 1, size) do
                        if a > 0.5 then
                            sprite[by][bx] = {r, g, b, 1}
                        end
                    end
                end
            end
        end
    end
    return sprite
end

function SpriteGenerator:applyGeometricStyle(sprite, settings)
    return sprite
end

-- ==============================================
-- ANIMATION SYSTEM MODULE
-- Novo suporte a durações específicas por frame e respiração
-- ==============================================
function AnimationSystem:new()
    local as = {}
    setmetatable(as, { __index = self })
    as.animations = {}
    as.currentAnimation = "idle"
    as.currentFrame = 1
    as.timer = 0
    as.isPlaying = true
    return as
end

-- Cria animações com durações por frame. Para alguns tipos predefinidos,
-- definimos sequências de duração para imitar princípios de animação 16‑bit.
function AnimationSystem:createAnimation(name, baseSprite, frameCount, settings)
    local frames = {}
    local durations = {}
    -- definir durações específicas para cada animação
    if name == "idle" then
        -- respiração lenta
        for i = 1, frameCount do durations[i] = settings.animationSpeed end
    elseif name == "walk_right" or name == "walk_left" then
        for i = 1, frameCount do durations[i] = settings.animationSpeed end
    elseif name == "attack" then
        -- wind‑up, impacto, recuo
        durations = { settings.animationSpeed*1.2, settings.animationSpeed*0.3, settings.animationSpeed*1.0 }
    elseif name == "hurt" then
        durations = { settings.animationSpeed*0.5, settings.animationSpeed*0.5 }
    elseif name == "death" then
        durations = { settings.animationSpeed*1.0, settings.animationSpeed*1.0, settings.animationSpeed*1.0 }
    else
        for i = 1, frameCount do durations[i] = settings.animationSpeed end
    end
    for i = 1, frameCount do
        local frame = Utils.deepCopy(baseSprite)
        if name == "idle" then
            frame = self:applyIdleTransform(frame, i, frameCount)
        elseif name == "walk_right" or name == "walk_left" then
            frame = self:applyWalkTransform(frame, i, frameCount, name == "walk_left")
        elseif name == "attack" then
            frame = self:applyAttackTransform(frame, i, frameCount)
        elseif name == "hurt" then
            frame = self:applyHurtTransform(frame, i, frameCount)
        elseif name == "death" then
            frame = self:applyDeathTransform(frame, i, frameCount)
        end
        frames[i] = frame
    end
    self.animations[name] = { frames = frames, frameCount = frameCount, durations = durations }
end

function AnimationSystem:applyIdleTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    local offset = math.sin(t * math.pi * 2) * 1
    local newSprite = Utils.deepCopy(sprite)
    for y = 1, size do
        for x = 1, size do
            local newY = y + math.floor(offset * (y / size))
            if newY >= 1 and newY <= size then
                newSprite[newY][x] = sprite[y][x]
            end
            -- respiração: variar brilho da cor principal
            if newSprite[y][x][4] > 0 then
                local factor = 1 + 0.05 * math.sin(t * math.pi * 2)
                newSprite[y][x] = Utils.adjustColor(newSprite[y][x], factor)
            end
        end
    end
    return newSprite
end

function AnimationSystem:applyWalkTransform(sprite, frame, totalFrames, isLeft)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    local offset = math.sin(t * math.pi * 2) * 2
    local newSprite = self:createEmptySprite(size)
    local xShift = math.floor(offset) * (isLeft and -1 or 1)
    for y = 1, size do
        for x = 1, size do
            local newX = x + xShift
            if newX >= 1 and newX <= size then
                newSprite[y][newX] = sprite[y][x]
            end
        end
    end
    -- movimentar pernas para cima e baixo de forma suave
    local legOffset = math.abs(math.sin(t * math.pi * 2)) * 2
    for y = size - math.floor(size * 0.3), size do
        for x = 1, size do
            if newSprite[y][x][4] > 0 then
                local ny = y + math.floor(legOffset)
                if ny <= size then
                    newSprite[ny][x] = newSprite[y][x]
                    if ny ~= y then newSprite[y][x] = {0,0,0,0} end
                end
            end
        end
    end
    return newSprite
end

function AnimationSystem:applyAttackTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    local newSprite = self:createEmptySprite(size)
    if frame == 1 then
        -- wind‑up: recuar 2 pixels
        for y = 1, size do
            for x = 1, size do
                local ny = y + 2
                if ny <= size then newSprite[ny][x] = sprite[y][x] end
            end
        end
    elseif frame == 2 then
        -- impacto: expandir 2 pixels e flash branco
        for y = 1, size do
            for x = 1, size do
                local ny = y - 1
                local nx = x + (math.sin(t * math.pi) > 0 and 1 or -1)
                if nx >= 1 and nx <= size and ny >= 1 and ny <= size then
                    local pix = sprite[y][x]
                    if pix[4] > 0 then
                        -- flash branco
                        newSprite[ny][nx] = {1,1,1,1}
                    end
                end
            end
        end
    else
        -- recuo: voltar à posição
        newSprite = Utils.deepCopy(sprite)
    end
    return newSprite
end

function AnimationSystem:applyHurtTransform(sprite, frame, totalFrames)
    local size = #sprite
    local newSprite = Utils.deepCopy(sprite)
    if frame == 1 then
        -- knockback 3 pixels
        for y = 1, size do
            for x = size, 1, -1 do
                local nx = x + 3
                if nx <= size then newSprite[y][nx] = sprite[y][x] end
            end
        end
    else
        -- flash vermelho
        for y = 1, size do
            for x = 1, size do
                if newSprite[y][x][4] > 0 then
                    newSprite[y][x] = {1, 0.3, 0.3, newSprite[y][x][4]}
                end
            end
        end
    end
    return newSprite
end

function AnimationSystem:applyDeathTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    local alpha = 1 - t
    local fallOffset = math.floor(t * size * 0.5)
    local newSprite = self:createEmptySprite(size)
    for y = 1, size do
        for x = 1, size do
            local ny = y + fallOffset
            local nx = x
            if ny <= size and sprite[y][x][4] > 0 then
                newSprite[ny][nx] = { sprite[y][x][1], sprite[y][x][2], sprite[y][x][3], sprite[y][x][4] * alpha }
            end
        end
    end
    return newSprite
end

function AnimationSystem:createEmptySprite(size)
    local sprite = {}
    for y = 1, size do
        sprite[y] = {}
        for x = 1, size do sprite[y][x] = {0,0,0,0} end
    end
    return sprite
end

function AnimationSystem:update(dt)
    if not self.isPlaying then return end
    self.timer = self.timer + dt
    local anim = self.animations[self.currentAnimation]
    if anim then
        local duration = anim.durations[self.currentFrame] or settings.animationSpeed
        if self.timer >= duration then
            self.timer = 0
            self.currentFrame = self.currentFrame + 1
            if self.currentFrame > anim.frameCount then
                self.currentFrame = 1
            end
        end
    end
end

function AnimationSystem:getCurrentFrame()
    local anim = self.animations[self.currentAnimation]
    if anim and anim.frames[self.currentFrame] then
        return anim.frames[self.currentFrame]
    end
    return nil
end

function AnimationSystem:setAnimation(name)
    if self.animations[name] then
        self.currentAnimation = name
        self.currentFrame = 1
        self.timer = 0
    end
end

-- ==============================================
-- UI MANAGER MODULE
-- Foram adicionados sliders e dropdowns para os novos parâmetros. Também incluímos
-- uma pré‑visualização multi‑escala para validar legibilidade em 1×, 2× e 4×.
-- ==============================================
function UIManager:new()
    local uiInstance = {}
    setmetatable(uiInstance, { __index = self })
    uiInstance.panels = {
        left = { x = 0, y = 0, width = 280, height = love.graphics.getHeight() },
        center = { x = 280, y = 0, width = love.graphics.getWidth() - 560, height = love.graphics.getHeight() - 160 },
        right = { x = love.graphics.getWidth() - 280, y = 0, width = 280, height = love.graphics.getHeight() },
        bottom = { x = 280, y = love.graphics.getHeight() - 160, width = love.graphics.getWidth() - 560, height = 160 }
    }
    uiInstance.controls = {}
    uiInstance.sliders = {}
    uiInstance.buttons = {}
    uiInstance.hoveredControl = nil
    uiInstance.activeControl = nil
    uiInstance.fonts = {
        small = love.graphics.newFont(11),
        regular = love.graphics.newFont(13),
        medium = love.graphics.newFont(16),
        large = love.graphics.newFont(20),
        title = love.graphics.newFont(24)
    }
    self:initializeControls(uiInstance)
    return uiInstance
end

function UIManager:initializeControls(uiInstance)
    local y = 50
    local spacing = 40
    local leftPadding = 20
    local controlWidth = 240
    uiInstance.title = { text = "PIXEL ART GENERATOR", x = leftPadding, y = 15 }
    uiInstance.controls.spriteType = { type = "dropdown", label = "Sprite Type", x = leftPadding, y = y, width = controlWidth, options = {"character", "weapon", "item", "tile"}, selected = 1 }
    y = y + spacing
    uiInstance.sliders.size = self:createSlider("Size", leftPadding, y, 8, 32, DEFAULT_SETTINGS.size)
    y = y + spacing
    uiInstance.controls.paletteType = { type = "dropdown", label = "Palette", x = leftPadding, y = y, width = controlWidth, options = {"NES", "GameBoy", "C64"}, selected = 1 }
    y = y + spacing
    uiInstance.sliders.complexity = self:createSlider("Complexity", leftPadding, y, 0, 100, DEFAULT_SETTINGS.complexity)
    y = y + spacing
    uiInstance.controls.symmetry = { type = "dropdown", label = "Symmetry", x = leftPadding, y = y, width = controlWidth, options = {"none", "vertical", "horizontal", "both"}, selected = 2 }
    y = y + spacing
    uiInstance.sliders.roughness = self:createSlider("Roughness", leftPadding, y, 0, 100, DEFAULT_SETTINGS.roughness)
    y = y + spacing
    uiInstance.sliders.colorCount = self:createSlider("Color Count", leftPadding, y, 2, 16, DEFAULT_SETTINGS.colorCount)
    y = y + spacing
    uiInstance.controls.visualSeed = { type = "input", label = "Visual Seed", x = leftPadding, y = y, width = controlWidth, value = tostring(os.time()) }
    y = y + spacing
    uiInstance.controls.structureSeed = { type = "input", label = "Structure Seed", x = leftPadding, y = y, width = controlWidth, value = tostring(os.time()) }
    y = y + spacing
    uiInstance.sliders.anatomyScale = self:createSlider("Anatomy Scale", leftPadding, y, 20, 100, DEFAULT_SETTINGS.anatomyScale)
    y = y + spacing
    uiInstance.controls.class = { type = "dropdown", label = "Class", x = leftPadding, y = y, width = controlWidth, options = {"warrior", "mage", "archer"}, selected = 1 }
    y = y + spacing
    uiInstance.sliders.detailLevel = self:createSlider("Detail Level", leftPadding, y, 0, 100, DEFAULT_SETTINGS.detailLevel)
    y = y + spacing
    uiInstance.controls.outline = { type = "checkbox", label = "Add Outline", x = leftPadding, y = y, checked = true }
    y = y + spacing
    uiInstance.sliders.frameCount = self:createSlider("Frame Count", leftPadding, y, 2, 8, DEFAULT_SETTINGS.frameCount)
    y = y + spacing
    uiInstance.sliders.animationSpeed = self:createSlider("Anim Speed", leftPadding, y, 0.05, 0.5, DEFAULT_SETTINGS.animationSpeed)
    y = y + spacing
    uiInstance.controls.style = { type = "dropdown", label = "Style", x = leftPadding, y = y, width = controlWidth, options = {"organic", "blocky", "geometric"}, selected = 1 }
    y = y + spacing
    -- novos controles
    uiInstance.sliders.bodyRatio = self:createSlider("Body Ratio", leftPadding, y, 2, 7, DEFAULT_SETTINGS.bodyRatio)
    y = y + spacing
    uiInstance.sliders.limbLength = self:createSlider("Limb Length", leftPadding, y, 20, 100, DEFAULT_SETTINGS.limbLength)
    y = y + spacing
    uiInstance.controls.silhouetteStyle = { type = "dropdown", label = "Silhouette", x = leftPadding, y = y, width = controlWidth, options = {"heroic", "chibi", "realistic"}, selected = 1 }
    y = y + spacing
    uiInstance.controls.lightDir = { type = "dropdown", label = "Light Dir", x = leftPadding, y = y, width = controlWidth, options = {"top-left", "top-right", "front"}, selected = 1 }
    y = y + spacing
    uiInstance.controls.weaponTrails = { type = "checkbox", label = "Weapon Trails", x = leftPadding, y = y, checked = false }
    y = y + spacing + 10
    -- botões
    local buttonY = love.graphics.getHeight() - 260
    uiInstance.buttons.generate = { label = "Generate [SPACE]", x = leftPadding, y = buttonY, width = 115, height = 35, color = COLORS.accent, action = function() ui:generateNewSprite() end }
    uiInstance.buttons.randomize = { label = "Randomize [R]", x = leftPadding + 125, y = buttonY, width = 115, height = 35, color = COLORS.warning, action = function() ui:randomizeSettings() end }
    buttonY = buttonY + 45
    uiInstance.buttons.save = { label = "Save Sprite [S]", x = leftPadding, y = buttonY, width = 115, height = 35, color = COLORS.success, action = function() ui:saveSprite() end }
    uiInstance.buttons.saveSheet = { label = "Save Sheet [A]", x = leftPadding + 125, y = buttonY, width = 115, height = 35, color = COLORS.success, action = function() ui:saveSpriteSheet() end }
    buttonY = buttonY + 45
    uiInstance.buttons.batch = { label = "Batch Generate [ENTER]", x = leftPadding, y = buttonY, width = controlWidth, height = 35, color = COLORS.accentDark, action = function() ui:batchGenerate() end }
end

function UIManager:createSlider(label, x, y, min, max, default)
    return { type = "slider", label = label, x = x, y = y, width = 240, min = min, max = max, value = default, percentage = (default - min) / (max - min) }
end

function UIManager:draw()
    love.graphics.setColor(COLORS.bg)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.left.x, self.panels.left.y, self.panels.left.width, self.panels.left.height)
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.left.width - 1, 0, 1, love.graphics.getHeight())
    love.graphics.setFont(self.fonts.title)
    love.graphics.setColor(COLORS.accent)
    love.graphics.print(self.title.text, self.title.x, self.title.y)
    love.graphics.setFont(self.fonts.regular)
    for _, slider in pairs(self.sliders) do self:drawSlider(slider) end
    for _, control in pairs(self.controls) do
        if control.type == "dropdown" then self:drawDropdown(control)
        elseif control.type == "checkbox" then self:drawCheckbox(control)
        elseif control.type == "input" then self:drawInput(control) end
    end
    for _, button in pairs(self.buttons) do self:drawButton(button) end
    -- área central
    love.graphics.setColor(COLORS.panelLight)
    love.graphics.rectangle("fill", self.panels.center.x, self.panels.center.y, self.panels.center.width, self.panels.center.height)
    if currentSprite then self:drawSpritePreviewMulti() else
        love.graphics.setFont(self.fonts.large)
        love.graphics.setColor(COLORS.textDim)
        local text = "Press SPACE to generate a sprite"
        local w = self.fonts.large:getWidth(text)
        love.graphics.print(text, self.panels.center.x + (self.panels.center.width - w) / 2, self.panels.center.y + self.panels.center.height / 2)
        love.graphics.setFont(self.fonts.regular)
    end
    -- painel direito (histórico)
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.right.x, self.panels.right.y, self.panels.right.width, self.panels.right.height)
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.right.x, 0, 1, love.graphics.getHeight())
    self:drawSpriteHistory()
    -- painel inferior (timeline)
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.bottom.x, self.panels.bottom.y, self.panels.bottom.width, self.panels.bottom.height)
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.bottom.x, self.panels.bottom.y, self.panels.bottom.width, 1)
    self:drawTimeline()
end

function UIManager:drawSlider(slider)
    love.graphics.setColor(COLORS.text)
    love.graphics.print(slider.label, slider.x, slider.y)
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(slider.x, slider.y + 18, slider.width, 6, 3)
    love.graphics.setColor(COLORS.accentDark)
    Utils.drawRoundedRect(slider.x, slider.y + 18, slider.width * slider.percentage, 6, 3)
    local handleX = slider.x + slider.percentage * slider.width
    love.graphics.setColor(COLORS.accent)
    love.graphics.circle("fill", handleX, slider.y + 21, 8)
    love.graphics.setColor(COLORS.text)
    local value = slider.value
    if slider.max <= 1 then value = string.format("%.2f", value) else value = string.format("%d", value) end
    love.graphics.setFont(self.fonts.small)
    local vw = self.fonts.small:getWidth(value)
    love.graphics.print(value, slider.x + slider.width - vw, slider.y)
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawDropdown(dropdown)
    love.graphics.setColor(COLORS.text)
    love.graphics.print(dropdown.label, dropdown.x, dropdown.y)
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(dropdown.x, dropdown.y + 18, dropdown.width, 24, 4)
    if dropdown.hovered then
        love.graphics.setColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.1)
        Utils.drawRoundedRect(dropdown.x, dropdown.y + 18, dropdown.width, 24, 4)
    end
    love.graphics.setColor(COLORS.text)
    love.graphics.print(dropdown.options[dropdown.selected], dropdown.x + 8, dropdown.y + 22)
    love.graphics.setColor(COLORS.textDim)
    love.graphics.print("▼", dropdown.x + dropdown.width - 20, dropdown.y + 22)
end

function UIManager:drawCheckbox(checkbox)
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(checkbox.x, checkbox.y, 20, 20, 4)
    if checkbox.checked then
        love.graphics.setColor(COLORS.accent)
        love.graphics.setLineWidth(3)
        love.graphics.line(checkbox.x + 5, checkbox.y + 10, checkbox.x + 8, checkbox.y + 14, checkbox.x + 15, checkbox.y + 6)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(COLORS.text)
    love.graphics.print(checkbox.label, checkbox.x + 28, checkbox.y + 2)
end

function UIManager:drawInput(input)
    love.graphics.setColor(COLORS.text)
    love.graphics.print(input.label, input.x, input.y)
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(input.x, input.y + 18, input.width, 24, 4)
    love.graphics.setColor(COLORS.text)
    love.graphics.print(input.value, input.x + 8, input.y + 22)
end

function UIManager:drawButton(button)
    local color = button.color or COLORS.accent
    love.graphics.setColor(color)
    Utils.drawRoundedRect(button.x, button.y, button.width, button.height, 6)
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.setFont(self.fonts.medium)
    local tw = self.fonts.medium:getWidth(button.label)
    local th = self.fonts.medium:getHeight()
    love.graphics.print(button.label, button.x + (button.width - tw)/2, button.y + (button.height - th)/2)
    love.graphics.setFont(self.fonts.regular)
end

-- Pré‑visualização multi‑escala: desenha o sprite em 1×, 2× e 4× lado a lado.
function UIManager:drawSpritePreviewMulti()
    local sprite = animation:getCurrentFrame() or currentSprite
    local size = #sprite
    local scales = {1, 2, 4}
    local totalWidth = 0
    for _, s in ipairs(scales) do totalWidth = totalWidth + size * s + 20 end
    local startX = self.panels.center.x + (self.panels.center.width - totalWidth + 20) / 2
    local yCenter = self.panels.center.y + (self.panels.center.height - size * scales[#scales]) / 2
    for _, scale in ipairs(scales) do
        local sx = startX
        local sy = yCenter
        for y = 1, size do
            for x = 1, size do
                local pix = sprite[y][x]
                if pix[4] > 0 then
                    love.graphics.setColor(pix[1], pix[2], pix[3], pix[4])
                    love.graphics.rectangle("fill", sx + (x - 1) * scale, sy + (y - 1) * scale, scale, scale)
                end
            end
        end
        startX = startX + size * scale + 20
    end
    -- texto informativo
    love.graphics.setColor(COLORS.text)
    love.graphics.setFont(self.fonts.small)
    love.graphics.print(size .. "x" .. size .. " px", self.panels.center.x + 20, self.panels.center.y + 20)
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawSpriteHistory()
    love.graphics.setFont(self.fonts.medium)
    love.graphics.setColor(COLORS.text)
    love.graphics.print("SPRITE HISTORY", self.panels.right.x + 20, 20)
    local y = 55
    local thumbSize = 72
    local spacing = 12
    local columns = 3
    love.graphics.setFont(self.fonts.small)
    for i, spr in ipairs(spriteHistory) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local x = self.panels.right.x + 20 + col * (thumbSize + spacing)
        local ty = y + row * (thumbSize + spacing)
        love.graphics.setColor(COLORS.panelLight)
        Utils.drawRoundedRect(x - 2, ty - 2, thumbSize + 4, thumbSize + 4, 4)
        local mx, my = love.mouse.getPosition()
        if mx >= x and mx <= x + thumbSize and my >= ty and my <= ty + thumbSize then
            love.graphics.setColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.2)
            Utils.drawRoundedRect(x - 2, ty - 2, thumbSize + 4, thumbSize + 4, 4)
        end
        self:drawSpriteThumbnail(spr, x, ty, thumbSize)
        love.graphics.setColor(COLORS.textDim)
        love.graphics.print("#" .. i, x + 2, ty + thumbSize - 12)
    end
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawSpriteThumbnail(sprite, x, y, size)
    local spriteSize = #sprite
    local scale = size / spriteSize
    for py = 1, spriteSize do
        for px = 1, spriteSize do
            local pix = sprite[py][px]
            if pix[4] > 0 then
                love.graphics.setColor(pix[1], pix[2], pix[3], pix[4])
                love.graphics.rectangle("fill", x + (px - 1) * scale, y + (py - 1) * scale, scale, scale)
            end
        end
    end
end

function UIManager:drawTimeline()
    love.graphics.setFont(self.fonts.medium)
    love.graphics.setColor(COLORS.text)
    love.graphics.print("ANIMATION TIMELINE", self.panels.bottom.x + 20, self.panels.bottom.y + 10)
    local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
    local buttonWidth = 80
    local buttonHeight = 25
    local buttonY = self.panels.bottom.y + 35
    for i, animType in ipairs(animTypes) do
        local buttonX = self.panels.bottom.x + 20 + (i - 1) * (buttonWidth + 5)
        if animation.currentAnimation == animType then love.graphics.setColor(COLORS.accent) else love.graphics.setColor(COLORS.panelLight) end
        Utils.drawRoundedRect(buttonX, buttonY, buttonWidth, buttonHeight, 4)
        love.graphics.setColor(animation.currentAnimation == animType and {0.1,0.1,0.1} or COLORS.text)
        love.graphics.setFont(self.fonts.small)
        local text = animType:upper()
        local tw = self.fonts.small:getWidth(text)
        love.graphics.print(text, buttonX + (buttonWidth - tw)/2, buttonY + 6)
    end
    local trackX = self.panels.bottom.x + 20
    local trackY = self.panels.bottom.y + 70
    local trackWidth = self.panels.bottom.width - 120
    local trackHeight = 30
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(trackX, trackY, trackWidth, trackHeight, 4)
    local anim = animation.animations[animation.currentAnimation]
    if anim then
        local frameWidth = trackWidth / anim.frameCount
        for i = 1, anim.frameCount do
            if i == animation.currentFrame then love.graphics.setColor(COLORS.accent) else love.graphics.setColor(COLORS.grid) end
            Utils.drawRoundedRect(trackX + (i - 1) * frameWidth + 2, trackY + 2, frameWidth - 4, trackHeight - 4, 2)
            love.graphics.setColor(i == animation.currentFrame and {0.1,0.1,0.1} or COLORS.text)
            love.graphics.setFont(self.fonts.regular)
            local ft = tostring(i)
            local tw = self.fonts.regular:getWidth(ft)
            love.graphics.print(ft, trackX + (i - 1) * frameWidth + frameWidth/2 - tw/2, trackY + 8)
        end
    end
    local playButton = { x = trackX + trackWidth + 10, y = trackY, width = 70, height = trackHeight }
    love.graphics.setColor(animation.isPlaying and COLORS.warning or COLORS.success)
    Utils.drawRoundedRect(playButton.x, playButton.y, playButton.width, playButton.height, 4)
    love.graphics.setColor(0.1,0.1,0.1)
    love.graphics.setFont(self.fonts.regular)
    local ptext = animation.isPlaying and "PAUSE" or "PLAY"
    local tw = self.fonts.regular:getWidth(ptext)
    love.graphics.print(ptext, playButton.x + (playButton.width - tw)/2, playButton.y + 8)
end

function UIManager:updateSettings()
    settings.spriteType = self.controls.spriteType.options[self.controls.spriteType.selected]
    settings.size = math.floor(self.sliders.size.value)
    settings.paletteType = self.controls.paletteType.options[self.controls.paletteType.selected]
    settings.complexity = self.sliders.complexity.value
    settings.symmetry = self.controls.symmetry.options[self.controls.symmetry.selected]
    settings.roughness = self.sliders.roughness.value
    settings.colorCount = math.floor(self.sliders.colorCount.value)
    settings.visualSeed = tonumber(self.controls.visualSeed.value) or os.time()
    settings.structureSeed = tonumber(self.controls.structureSeed.value) or os.time()
    settings.anatomyScale = self.sliders.anatomyScale.value
    settings.class = self.controls.class.options[self.controls.class.selected]
    settings.detailLevel = self.sliders.detailLevel.value
    settings.outline = self.controls.outline.checked
    settings.frameCount = math.floor(self.sliders.frameCount.value)
    settings.animationSpeed = self.sliders.animationSpeed.value
    settings.style = self.controls.style.options[self.controls.style.selected]
    settings.bodyRatio = self.sliders.bodyRatio.value
    settings.limbLength = self.sliders.limbLength.value
    settings.silhouetteStyle = self.controls.silhouetteStyle.options[self.controls.silhouetteStyle.selected]
    settings.lightDir = self.controls.lightDir.options[self.controls.lightDir.selected]
    settings.weaponTrails = self.controls.weaponTrails.checked
    palette.currentPalette = settings.paletteType
end

function UIManager:generateNewSprite()
    self:updateSettings()
    currentSprite = generator:generate(settings)
    table.insert(spriteHistory, 1, currentSprite)
    if #spriteHistory > maxHistory then table.remove(spriteHistory) end
    local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
    for _, t in ipairs(animTypes) do animation:createAnimation(t, currentSprite, settings.frameCount, settings) end
end

function UIManager:randomizeSettings()
    self.sliders.size.value = math.random(8, 32)
    self.sliders.complexity.value = math.random(0, 100)
    self.sliders.roughness.value = math.random(0, 100)
    self.sliders.colorCount.value = math.random(2, 16)
    self.sliders.anatomyScale.value = math.random(20, 100)
    self.sliders.detailLevel.value = math.random(0, 100)
    self.sliders.frameCount.value = math.random(2, 8)
    self.sliders.animationSpeed.value = math.random() * 0.4 + 0.05
    self.sliders.bodyRatio.value = math.random(2, 7)
    self.sliders.limbLength.value = math.random(20, 100)
    self.controls.spriteType.selected = math.random(1, #self.controls.spriteType.options)
    self.controls.paletteType.selected = math.random(1, #self.controls.paletteType.options)
    self.controls.symmetry.selected = math.random(1, #self.controls.symmetry.options)
    self.controls.class.selected = math.random(1, #self.controls.class.options)
    self.controls.style.selected = math.random(1, #self.controls.style.options)
    self.controls.silhouetteStyle.selected = math.random(1, #self.controls.silhouetteStyle.options)
    self.controls.lightDir.selected = math.random(1, #self.controls.lightDir.options)
    self.controls.outline.checked = math.random() > 0.5
    self.controls.weaponTrails.checked = math.random() > 0.5
    self.controls.visualSeed.value = tostring(os.time() + math.random(1000))
    self.controls.structureSeed.value = tostring(os.time() + math.random(1000))
    -- atualizar porcentagens
    for _, slider in pairs(self.sliders) do slider.percentage = (slider.value - slider.min) / (slider.max - slider.min) end
end

function UIManager:saveSprite()
    if currentSprite then export:saveSprite(currentSprite, "sprite_" .. os.time() .. ".png") end
end

function UIManager:saveSpriteSheet()
    local anim = animation.animations[animation.currentAnimation]
    if anim then export:saveSpriteSheet(anim, "spritesheet_" .. os.time() .. ".png") end
end

function UIManager:batchGenerate()
    for i = 1, 10 do self:randomizeSettings(); self:generateNewSprite() end
end

function UIManager:mousepressed(x,y,button)
    if button == 1 then
        for _, slider in pairs(self.sliders) do
            if self:isPointInRect(x,y, slider.x - 10, slider.y + 10, slider.width + 20, 20) then
                self.activeControl = slider
                self:updateSliderValue(slider, x)
            end
        end
        for _, btn in pairs(self.buttons) do
            if self:isPointInRect(x,y, btn.x, btn.y, btn.width, btn.height) then btn.action() end
        end
        for _, dropdown in pairs(self.controls) do
            if dropdown.type == "dropdown" and self:isPointInRect(x,y, dropdown.x, dropdown.y + 18, dropdown.width, 24) then
                dropdown.selected = dropdown.selected % #dropdown.options + 1
            end
        end
        for _, checkbox in pairs(self.controls) do
            if checkbox.type == "checkbox" and self:isPointInRect(x,y, checkbox.x, checkbox.y, 20, 20) then
                checkbox.checked = not checkbox.checked
            end
        end
        local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
        local buttonWidth = 80
        local buttonHeight = 25
        local buttonY = self.panels.bottom.y + 35
        for i, animType in ipairs(animTypes) do
            local buttonX = self.panels.bottom.x + 20 + (i - 1) * (buttonWidth + 5)
            if self:isPointInRect(x,y, buttonX, buttonY, buttonWidth, buttonHeight) then animation:setAnimation(animType) end
        end
        local trackWidth = self.panels.bottom.width - 120
        local playButton = { x = self.panels.bottom.x + 20 + trackWidth + 10, y = self.panels.bottom.y + 70, width = 70, height = 30 }
        if self:isPointInRect(x,y, playButton.x, playButton.y, playButton.width, playButton.height) then animation.isPlaying = not animation.isPlaying end
        self:checkSpriteHistoryClick(x,y)
    end
end

function UIManager:mousereleased(x,y,button)
    if button == 1 then self.activeControl = nil end
end

function UIManager:mousemoved(x,y)
    if self.activeControl and self.activeControl.type == "slider" then self:updateSliderValue(self.activeControl, x) end
    for _, btn in pairs(self.buttons) do btn.hovered = self:isPointInRect(x,y, btn.x, btn.y, btn.width, btn.height) end
    for _, dropdown in pairs(self.controls) do if dropdown.type == "dropdown" then dropdown.hovered = self:isPointInRect(x,y, dropdown.x, dropdown.y + 18, dropdown.width, 24) end end
end

function UIManager:isPointInRect(px,py,x,y,w,h) return px >= x and px <= x + w and py >= y and py <= y + h end
function UIManager:updateSliderValue(slider, x)
    slider.percentage = Utils.clamp((x - slider.x) / slider.width, 0, 1)
    slider.value = slider.min + (slider.max - slider.min) * slider.percentage
end
function UIManager:checkSpriteHistoryClick(x,y)
    local thumbSize = 72
    local spacing = 12
    local startY = 55
    local columns = 3
    for i, spr in ipairs(spriteHistory) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local tx = self.panels.right.x + 20 + col * (thumbSize + spacing)
        local ty = startY + row * (thumbSize + spacing)
        if self:isPointInRect(x,y, tx, ty, thumbSize, thumbSize) then
            currentSprite = spr
            local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
            for _, t in ipairs(animTypes) do animation:createAnimation(t, currentSprite, settings.frameCount, settings) end
            break
        end
    end
end

-- ==============================================
-- EXPORT MANAGER MODULE
-- ==============================================
function ExportManager:new()
    local em = {}
    setmetatable(em, { __index = self })
    return em
end
function ExportManager:saveSprite(sprite, filename)
    local size = #sprite
    local imageData = love.image.newImageData(size, size)
    for y = 1, size do
        for x = 1, size do
            local pix = sprite[y][x]
            imageData:setPixel(x - 1, y - 1, pix[1], pix[2], pix[3], pix[4])
        end
    end
    imageData:encode("png", filename)
    print("Saved sprite to: " .. filename)
end
function ExportManager:saveSpriteSheet(anim, filename)
    local frames = anim.frames
    local frameCount = anim.frameCount
    local size = #frames[1]
    local sheetWidth = size * frameCount
    local imageData = love.image.newImageData(sheetWidth, size)
    for i, frame in ipairs(frames) do
        local offsetX = (i - 1) * size
        for y = 1, size do
            for x = 1, size do
                local pix = frame[y][x]
                imageData:setPixel(offsetX + x - 1, y - 1, pix[1], pix[2], pix[3], pix[4])
            end
        end
    end
    imageData:encode("png", filename)
    print("Saved sprite sheet to: " .. filename)
end

-- ==============================================
-- PRESET MANAGER MODULE
-- ==============================================
function PresetManager:new()
    local pm = {}
    setmetatable(pm, { __index = self })
    pm.presets = {}
    return pm
end
function PresetManager:savePreset(slot, s)
    self.presets[slot] = Utils.deepCopy(s)
    print("Saved preset to slot " .. slot)
end
function PresetManager:loadPreset(slot)
    if self.presets[slot] then return Utils.deepCopy(self.presets[slot]) end
    return nil
end

-- ==============================================
-- MAIN LÖVE2D FUNCTIONS
-- ==============================================
function love.load()
    love.window.setTitle("Pixel Art Sprite Generator Improved")
    love.window.setMode(1280, 900, {resizable = false})
    generator = SpriteGenerator:new()
    animation = AnimationSystem:new()
    ui = UIManager:new()
    palette = PaletteManager:new()
    export = ExportManager:new()
    preset = PresetManager:new()
    for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end
    ui:generateNewSprite()
end

function love.update(dt)
    if animation then
        animation:update(dt)
    end
end

function love.draw()
    if ui then
        ui:draw()
    end
end

-- ⚠️ AQUI ESTÃO AS CORREÇÕES PRINCIPAIS:
function love.mousepressed(x, y, button) 
    if ui then -- ← VERIFICAÇÃO CRUCIAL
        ui:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button) 
    if ui then -- ← VERIFICAÇÃO CRUCIAL
        ui:mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y) 
    if ui then -- ← VERIFICAÇÃO CRUCIAL
        ui:mousemoved(x, y)
    end
end


function love.draw()
    ui:draw()
end
function love.keypressed(key)
    if not ui then return end -- ← VERIFICAÇÃO CRUCIAL
    
    if key == "space" then 
        ui:generateNewSprite() 
    elseif key == "r" then 
        ui:randomizeSettings() 
    elseif key == "s" then 
        ui:saveSprite() 
    elseif key == "a" then 
        ui:saveSpriteSheet() 
    elseif key == "return" then 
        ui:batchGenerate() 
    elseif key == "tab" then 
        local dd = ui.controls.spriteType
        if dd then
            dd.selected = dd.selected % #dd.options + 1
        end
    elseif tonumber(key) and tonumber(key) >= 1 and tonumber(key) <= 9 then 
        if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then 
            preset:savePreset(tonumber(key), settings) 
        else 
            local loaded = preset:loadPreset(tonumber(key))
            if loaded then 
                settings = loaded
                print("Loaded preset " .. key) 
            end 
        end 
    end
end