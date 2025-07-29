-- main.lua - Gerador de Sprites Pixel Art
-- Sistema completo de geração procedural com animação e interface melhorada

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

-- Configurações padrão
local DEFAULT_SETTINGS = {
    spriteType = "character",
    size = 16,
    paletteType = "NES",
    complexity = 50,
    symmetry = "vertical",
    roughness = 30,
    colorCount = 6,
    seed = os.time(),
    anatomyScale = 50,
    class = "warrior",
    detailLevel = 50,
    outline = true,
    frameCount = 4,
    animationSpeed = 0.1,
    style = "organic"
}

-- ==============================================
-- UTILS MODULE
-- ==============================================
function Utils.clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.noise(x, y, seed)
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
    
    -- Simple shuffle based on seed
    math.randomseed(seed)
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        p[i], p[j] = p[j], p[i]
    end
    
    local function perm(val)
        return p[val % 256]
    end
    
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

-- ==============================================
-- PALETTE MANAGER MODULE
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

function PaletteManager:getRandomColor(settings)
    local palette = self:getPalette()
    local maxColors = math.min(settings.colorCount, #palette)
    local index = math.random(1, maxColors)
    return palette[index]
end

-- ==============================================
-- SPRITE GENERATOR MODULE
-- ==============================================
function SpriteGenerator:new()
    local sg = {}
    setmetatable(sg, { __index = self })
    
    sg.generators = {
        character = function(self, settings) return self:generateCharacter(settings) end,
        weapon = function(self, settings) return self:generateWeapon(settings) end,
        item = function(self, settings) return self:generateItem(settings) end,
        tile = function(self, settings) return self:generateTile(settings) end
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
            sprite[y][x] = {0, 0, 0, 0} -- RGBA
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

function SpriteGenerator:addOutline(sprite)
    local size = #sprite
    local outlined = self:createEmptySprite(size)
    
    -- Copy original sprite
    for y = 1, size do
        for x = 1, size do
            outlined[y][x] = Utils.deepCopy(sprite[y][x])
        end
    end
    
    -- Add outline
    for y = 1, size do
        for x = 1, size do
            if sprite[y][x][4] > 0 then -- If pixel is not transparent
                -- Check all 8 directions
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        if dx ~= 0 or dy ~= 0 then
                            local ny, nx = y + dy, x + dx
                            if ny >= 1 and ny <= size and nx >= 1 and nx <= size then
                                if sprite[ny][nx][4] == 0 then -- If neighbor is transparent
                                    outlined[ny][nx] = {0, 0, 0, 1} -- Black outline
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

function SpriteGenerator:generateCharacter(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.seed)
    
    -- Character structure based on class
    local structures = {
        warrior = {
            headSize = 0.3,
            bodyWidth = 0.4,
            shoulderWidth = 0.5,
            legSpread = 0.3
        },
        mage = {
            headSize = 0.35,
            bodyWidth = 0.3,
            shoulderWidth = 0.35,
            legSpread = 0.2
        },
        archer = {
            headSize = 0.28,
            bodyWidth = 0.35,
            shoulderWidth = 0.4,
            legSpread = 0.25
        }
    }
    
    local struct = structures[settings.class] or structures.warrior
    local scale = settings.anatomyScale / 50
    
    -- Generate head
    local headStart = math.floor(size * 0.1)
    local headSize = math.floor(size * struct.headSize * scale)
    local headCenterX = math.floor(size / 2)
    
    for y = headStart, headStart + headSize do
        for x = headCenterX - math.floor(headSize/2), headCenterX + math.floor(headSize/2) do
            if x > 0 and x <= size and y > 0 and y <= size then
                local dist = math.sqrt((x - headCenterX)^2 + (y - headStart - headSize/2)^2)
                if dist < headSize/2 then
                    local noise = Utils.noise(x * 0.3, y * 0.3, settings.seed)
                    if noise > -0.3 then
                        sprite[y][x] = {palette:getRandomColor(settings)[1], 
                                      palette:getRandomColor(settings)[2], 
                                      palette:getRandomColor(settings)[3], 1}
                    end
                end
            end
        end
    end
    
    -- Generate body
    local bodyStart = headStart + headSize
    local bodyHeight = math.floor(size * 0.4 * scale)
    local bodyWidth = math.floor(size * struct.bodyWidth * scale)
    
    for y = bodyStart, math.min(bodyStart + bodyHeight, size) do
        local widthAtY = bodyWidth * (1 - (y - bodyStart) / bodyHeight * 0.2)
        for x = headCenterX - math.floor(widthAtY/2), headCenterX + math.floor(widthAtY/2) do
            if x > 0 and x <= size and y > 0 and y <= size then
                local noise = Utils.noise(x * 0.2, y * 0.2, settings.seed + 100)
                if noise > -0.4 then
                    sprite[y][x] = {palette:getRandomColor(settings)[1], 
                                  palette:getRandomColor(settings)[2], 
                                  palette:getRandomColor(settings)[3], 1}
                end
            end
        end
    end
    
    -- Generate arms
    local armStart = bodyStart + math.floor(bodyHeight * 0.2)
    local armLength = math.floor(size * 0.3 * scale)
    local shoulderWidth = math.floor(size * struct.shoulderWidth * scale)
    
    -- Left arm
    for i = 0, armLength do
        local x = headCenterX - shoulderWidth/2 - i/2
        local y = armStart + i
        if x > 0 and x <= size and y > 0 and y <= size then
            sprite[math.floor(y)][math.floor(x)] = {palette:getRandomColor(settings)[1], 
                                                   palette:getRandomColor(settings)[2], 
                                                   palette:getRandomColor(settings)[3], 1}
        end
    end
    
    -- Generate legs
    local legStart = bodyStart + bodyHeight
    local legHeight = size - legStart - 1
    local legSpread = math.floor(size * struct.legSpread * scale)
    
    -- Left leg
    for i = 0, legHeight do
        local x = headCenterX - legSpread/2
        local y = legStart + i
        if x > 0 and x <= size and y > 0 and y <= size then
            sprite[math.floor(y)][math.floor(x)] = {palette:getRandomColor(settings)[1], 
                                                   palette:getRandomColor(settings)[2], 
                                                   palette:getRandomColor(settings)[3], 1}
        end
    end
    
    -- Apply symmetry
    sprite = self:applySymmetry(sprite, settings.symmetry)
    
    -- Apply outline if enabled
    if settings.outline then
        sprite = self:addOutline(sprite)
    end
    
    -- Apply style modifications
    if settings.style == "blocky" then
        sprite = self:applyBlockyStyle(sprite, settings)
    elseif settings.style == "geometric" then
        sprite = self:applyGeometricStyle(sprite, settings)
    end
    
    return sprite
end

function SpriteGenerator:generateWeapon(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.seed)
    
    -- Weapon types
    local weaponTypes = {
        sword = function()
            -- Generate blade
            local bladeLength = math.floor(size * 0.7)
            local bladeWidth = math.floor(size * 0.15)
            local handleLength = math.floor(size * 0.3)
            
            -- Blade
            for y = 1, bladeLength do
                local width = bladeWidth * (1 - y / bladeLength * 0.5)
                for x = size/2 - width/2, size/2 + width/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.8, 0.8, 0.9, 1}
                    end
                end
            end
            
            -- Handle
            for y = bladeLength, bladeLength + handleLength do
                for x = size/2 - 1, size/2 + 1 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.4, 0.2, 0.1, 1}
                    end
                end
            end
            
            -- Guard
            local guardY = bladeLength
            for x = size/2 - 3, size/2 + 3 do
                if x > 0 and x <= size and guardY > 0 and guardY <= size then
                    sprite[guardY][math.floor(x)] = {0.6, 0.6, 0.7, 1}
                end
            end
        end,
        
        axe = function()
            -- Generate axe head
            local headSize = math.floor(size * 0.4)
            local handleLength = math.floor(size * 0.8)
            
            -- Handle
            for y = 1, handleLength do
                local x = size/2
                if x > 0 and x <= size and y > 0 and y <= size then
                    sprite[math.floor(y)][math.floor(x)] = {0.4, 0.2, 0.1, 1}
                end
            end
            
            -- Axe head
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
            -- Generate staff
            local length = math.floor(size * 0.9)
            local orbSize = math.floor(size * 0.2)
            
            -- Shaft
            for y = orbSize, length do
                local x = size/2
                if x > 0 and x <= size and y > 0 and y <= size then
                    sprite[math.floor(y)][math.floor(x)] = {0.5, 0.3, 0.2, 1}
                end
            end
            
            -- Orb
            local orbCenter = orbSize/2
            for y = 1, orbSize do
                for x = size/2 - orbSize/2, size/2 + orbSize/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local dist = math.sqrt((x - size/2)^2 + (y - orbCenter)^2)
                        if dist < orbSize/2 then
                            local color = palette:getRandomColor(settings)
                            sprite[math.floor(y)][math.floor(x)] = {color[1], color[2], color[3], 1}
                        end
                    end
                end
            end
        end
    }
    
    -- Select weapon type based on seed
    local types = {"sword", "axe", "staff"}
    local selectedType = types[(settings.seed % #types) + 1]
    weaponTypes[selectedType]()
    
    -- Apply effects based on complexity
    if settings.complexity > 70 then
        -- Add glow effect
        for y = 1, size do
            for x = 1, size do
                if sprite[y][x][4] > 0 then
                    local noise = Utils.noise(x * 0.5, y * 0.5, settings.seed)
                    if noise > 0.3 then
                        sprite[y][x][1] = math.min(1, sprite[y][x][1] + 0.2)
                        sprite[y][x][2] = math.min(1, sprite[y][x][2] + 0.2)
                        sprite[y][x][3] = math.min(1, sprite[y][x][3] + 0.2)
                    end
                end
            end
        end
    end
    
    -- Apply symmetry
    sprite = self:applySymmetry(sprite, settings.symmetry)
    
    -- Apply outline if enabled
    if settings.outline then
        sprite = self:addOutline(sprite)
    end
    
    return sprite
end

function SpriteGenerator:generateItem(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.seed)
    
    -- Item types
    local itemTypes = {
        potion = function()
            -- Generate potion bottle
            local bottleHeight = math.floor(size * 0.7)
            local bottleWidth = math.floor(size * 0.4)
            local neckHeight = math.floor(size * 0.2)
            
            -- Bottle body
            for y = size - bottleHeight, size do
                local width = bottleWidth * (0.8 + 0.2 * math.sin((y - size + bottleHeight) / bottleHeight * math.pi))
                for x = size/2 - width/2, size/2 + width/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        local color = palette:getRandomColor(settings)
                        sprite[math.floor(y)][math.floor(x)] = {color[1] * 0.8, color[2] * 0.8, color[3], 0.9}
                    end
                end
            end
            
            -- Neck
            for y = size - bottleHeight - neckHeight, size - bottleHeight do
                for x = size/2 - 1, size/2 + 1 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.8, 0.8, 0.8, 1}
                    end
                end
            end
            
            -- Cork
            local corkY = size - bottleHeight - neckHeight
            for x = size/2 - 2, size/2 + 2 do
                if x > 0 and x <= size and corkY > 0 and corkY <= size then
                    sprite[corkY][math.floor(x)] = {0.6, 0.4, 0.3, 1}
                end
            end
        end,
        
        gem = function()
            -- Generate gem
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
                            local color = palette:getRandomColor(settings)
                            local brightness = 0.7 + 0.3 * (facet % 2)
                            
                            sprite[math.floor(y)][math.floor(x)] = {
                                color[1] * brightness,
                                color[2] * brightness,
                                color[3] * brightness,
                                1
                            }
                        end
                    end
                end
            end
        end,
        
        chest = function()
            -- Generate chest
            local chestHeight = math.floor(size * 0.5)
            local chestWidth = math.floor(size * 0.7)
            local startY = size - chestHeight
            
            -- Chest body
            for y = startY, size do
                for x = size/2 - chestWidth/2, size/2 + chestWidth/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.5, 0.3, 0.1, 1}
                    end
                end
            end
            
            -- Lid
            for y = startY - 2, startY do
                for x = size/2 - chestWidth/2, size/2 + chestWidth/2 do
                    if x > 0 and x <= size and y > 0 and y <= size then
                        sprite[math.floor(y)][math.floor(x)] = {0.6, 0.4, 0.2, 1}
                    end
                end
            end
            
            -- Lock
            local lockX = size/2
            local lockY = startY + chestHeight/2
            if lockX > 0 and lockX <= size and lockY > 0 and lockY <= size then
                sprite[math.floor(lockY)][math.floor(lockX)] = {0.8, 0.7, 0.1, 1}
            end
        end
    }
    
    -- Select item type
    local types = {"potion", "gem", "chest"}
    local selectedType = types[(settings.seed % #types) + 1]
    itemTypes[selectedType]()
    
    -- Apply outline if enabled
    if settings.outline then
        sprite = self:addOutline(sprite)
    end
    
    return sprite
end

function SpriteGenerator:generateTile(settings)
    local size = settings.size
    local sprite = self:createEmptySprite(size)
    math.randomseed(settings.seed)
    
    -- Base color
    local baseColor = palette:getRandomColor(settings)
    
    -- Fill with base color
    for y = 1, size do
        for x = 1, size do
            sprite[y][x] = {baseColor[1], baseColor[2], baseColor[3], 1}
        end
    end
    
    -- Add texture based on complexity
    local noiseScale = 0.1 + (settings.complexity / 100) * 0.4
    
    for y = 1, size do
        for x = 1, size do
            local noise = Utils.noise(x * noiseScale, y * noiseScale, settings.seed)
            
            if noise > 0.3 then
                local color2 = palette:getRandomColor(settings)
                sprite[y][x] = {
                    Utils.lerp(baseColor[1], color2[1], 0.3),
                    Utils.lerp(baseColor[2], color2[2], 0.3),
                    Utils.lerp(baseColor[3], color2[3], 0.3),
                    1
                }
            elseif noise < -0.3 then
                sprite[y][x] = {
                    baseColor[1] * 0.8,
                    baseColor[2] * 0.8,
                    baseColor[3] * 0.8,
                    1
                }
            end
        end
    end
    
    -- Add pattern based on style
    if settings.style == "geometric" then
        -- Add grid pattern
        local gridSize = math.floor(size / 4)
        for y = 1, size do
            for x = 1, size do
                if x % gridSize == 0 or y % gridSize == 0 then
                    sprite[y][x][1] = sprite[y][x][1] * 0.7
                    sprite[y][x][2] = sprite[y][x][2] * 0.7
                    sprite[y][x][3] = sprite[y][x][3] * 0.7
                end
            end
        end
    end
    
    return sprite
end

function SpriteGenerator:applyBlockyStyle(sprite, settings)
    local size = #sprite
    local blockSize = math.max(2, math.floor(size / 8))
    
    for y = 1, size, blockSize do
        for x = 1, size, blockSize do
            -- Get average color for block
            local r, g, b, a = 0, 0, 0, 0
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
                
                -- Apply average color to block
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
    -- This would apply geometric patterns to the sprite
    -- For now, just return the sprite as-is
    return sprite
end

-- ==============================================
-- ANIMATION SYSTEM MODULE
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

function AnimationSystem:createAnimation(name, baseSprite, frameCount, settings)
    local frames = {}
    
    for i = 1, frameCount do
        local frame = Utils.deepCopy(baseSprite)
        
        -- Apply animation transformations based on type
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
    
    self.animations[name] = {
        frames = frames,
        frameCount = frameCount,
        speed = settings.animationSpeed
    }
end

function AnimationSystem:applyIdleTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    local offset = math.sin(t * math.pi * 2) * 1
    
    -- Subtle breathing animation
    local newSprite = Utils.deepCopy(sprite)
    
    -- Shift pixels slightly
    for y = 1, size do
        for x = 1, size do
            local newY = y + math.floor(offset * (y / size))
            if newY >= 1 and newY <= size then
                newSprite[newY][x] = sprite[y][x]
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
    
    -- Horizontal movement
    local xShift = math.floor(offset) * (isLeft and -1 or 1)
    
    for y = 1, size do
        for x = 1, size do
            local newX = x + xShift
            if newX >= 1 and newX <= size then
                newSprite[y][newX] = sprite[y][x]
            end
        end
    end
    
    -- Add leg movement
    local legOffset = math.abs(math.sin(t * math.pi * 2)) * 2
    for y = size - math.floor(size * 0.3), size do
        for x = 1, size do
            local newY = y + math.floor(legOffset * ((y - (size - size * 0.3)) / (size * 0.3)))
            if newY >= 1 and newY <= size and newSprite[y][x][4] > 0 then
                newSprite[newY][x] = newSprite[y][x]
                if newY ~= y then
                    newSprite[y][x] = {0, 0, 0, 0}
                end
            end
        end
    end
    
    return newSprite
end

function AnimationSystem:applyAttackTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    
    -- Attack animation - lean forward and back
    local angle = math.sin(t * math.pi) * 0.3
    local newSprite = self:createEmptySprite(size)
    
    for y = 1, size do
        for x = 1, size do
            local cx, cy = size/2, size/2
            local dx, dy = x - cx, y - cy
            
            -- Rotate around center
            local newX = math.floor(cx + dx * math.cos(angle) - dy * math.sin(angle))
            local newY = math.floor(cy + dx * math.sin(angle) + dy * math.cos(angle))
            
            if newX >= 1 and newX <= size and newY >= 1 and newY <= size then
                newSprite[newY][newX] = sprite[y][x]
            end
        end
    end
    
    return newSprite
end

function AnimationSystem:applyHurtTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    
    -- Flash red
    local newSprite = Utils.deepCopy(sprite)
    local flashIntensity = math.sin(t * math.pi * 4) * 0.5 + 0.5
    
    for y = 1, size do
        for x = 1, size do
            if newSprite[y][x][4] > 0 then
                newSprite[y][x][1] = math.min(1, newSprite[y][x][1] + flashIntensity * 0.5)
                newSprite[y][x][2] = newSprite[y][x][2] * (1 - flashIntensity * 0.5)
                newSprite[y][x][3] = newSprite[y][x][3] * (1 - flashIntensity * 0.5)
            end
        end
    end
    
    return newSprite
end

function AnimationSystem:applyDeathTransform(sprite, frame, totalFrames)
    local size = #sprite
    local t = (frame - 1) / (totalFrames - 1)
    
    -- Fade out and fall
    local newSprite = Utils.deepCopy(sprite)
    local alpha = 1 - t
    local fallOffset = math.floor(t * size * 0.5)
    
    -- Apply fall and fade
    local tempSprite = self:createEmptySprite(size)
    
    for y = 1, size do
        for x = 1, size do
            local newY = y + fallOffset
            if newY >= 1 and newY <= size and newSprite[y][x][4] > 0 then
                tempSprite[newY][x] = {
                    newSprite[y][x][1],
                    newSprite[y][x][2],
                    newSprite[y][x][3],
                    newSprite[y][x][4] * alpha
                }
            end
        end
    end
    
    return tempSprite
end

function AnimationSystem:createEmptySprite(size)
    local sprite = {}
    for y = 1, size do
        sprite[y] = {}
        for x = 1, size do
            sprite[y][x] = {0, 0, 0, 0}
        end
    end
    return sprite
end

function AnimationSystem:update(dt)
    if not self.isPlaying then return end
    
    self.timer = self.timer + dt
    
    local currentAnim = self.animations[self.currentAnimation]
    if currentAnim and self.timer >= currentAnim.speed then
        self.timer = 0
        self.currentFrame = self.currentFrame + 1
        if self.currentFrame > currentAnim.frameCount then
            self.currentFrame = 1
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
-- ==============================================
function UIManager:new()
    local uiInstance = {}
    setmetatable(uiInstance, { __index = self })
    
    uiInstance.panels = {
        left = { x = 0, y = 0, width = 280, height = love.graphics.getHeight() },
        center = { x = 280, y = 0, width = love.graphics.getWidth() - 560, height = love.graphics.getHeight() - 120 },
        right = { x = love.graphics.getWidth() - 280, y = 0, width = 280, height = love.graphics.getHeight() },
        bottom = { x = 280, y = love.graphics.getHeight() - 120, width = love.graphics.getWidth() - 560, height = 120 }
    }
    
    uiInstance.controls = {}
    uiInstance.sliders = {}
    uiInstance.buttons = {}
    uiInstance.hoveredControl = nil
    uiInstance.activeControl = nil
    
    -- Font setup
    uiInstance.fonts = {
        small = love.graphics.newFont(11),
        regular = love.graphics.newFont(13),
        medium = love.graphics.newFont(16),
        large = love.graphics.newFont(20),
        title = love.graphics.newFont(24)
    }
    
    -- Initialize controls
    self:initializeControls(uiInstance)
    
    return uiInstance
end

function UIManager:initializeControls(uiInstance)
    local y = 50
    local spacing = 40
    local leftPadding = 20
    local controlWidth = 240
    
    -- Title
    uiInstance.title = {
        text = "PIXEL ART GENERATOR",
        x = leftPadding,
        y = 15
    }
    
    -- Sprite Type Dropdown
    uiInstance.controls.spriteType = {
        type = "dropdown",
        label = "Sprite Type",
        x = leftPadding, y = y,
        width = controlWidth,
        options = {"character", "weapon", "item", "tile"},
        selected = 1
    }
    y = y + spacing
    
    -- Size Slider
    uiInstance.sliders.size = self:createSlider("Size", leftPadding, y, 8, 32, 16)
    y = y + spacing
    
    -- Palette Dropdown
    uiInstance.controls.paletteType = {
        type = "dropdown",
        label = "Palette",
        x = leftPadding, y = y,
        width = controlWidth,
        options = {"NES", "GameBoy", "C64"},
        selected = 1
    }
    y = y + spacing
    
    -- Complexity Slider
    uiInstance.sliders.complexity = self:createSlider("Complexity", leftPadding, y, 0, 100, 50)
    y = y + spacing
    
    -- Symmetry Dropdown
    uiInstance.controls.symmetry = {
        type = "dropdown",
        label = "Symmetry",
        x = leftPadding, y = y,
        width = controlWidth,
        options = {"none", "vertical", "horizontal", "both"},
        selected = 2
    }
    y = y + spacing
    
    -- Roughness Slider
    uiInstance.sliders.roughness = self:createSlider("Roughness", leftPadding, y, 0, 100, 30)
    y = y + spacing
    
    -- Color Count Slider
    uiInstance.sliders.colorCount = self:createSlider("Color Count", leftPadding, y, 2, 16, 6)
    y = y + spacing
    
    -- Seed Input
    uiInstance.controls.seed = {
        type = "input",
        label = "Seed",
        x = leftPadding, y = y,
        width = controlWidth,
        value = tostring(os.time())
    }
    y = y + spacing
    
    -- Anatomy Scale Slider (for characters)
    uiInstance.sliders.anatomyScale = self:createSlider("Anatomy Scale", leftPadding, y, 20, 100, 50)
    y = y + spacing
    
    -- Class Dropdown (for characters)
    uiInstance.controls.class = {
        type = "dropdown",
        label = "Class",
        x = leftPadding, y = y,
        width = controlWidth,
        options = {"warrior", "mage", "archer"},
        selected = 1
    }
    y = y + spacing
    
    -- Detail Level Slider
    uiInstance.sliders.detailLevel = self:createSlider("Detail Level", leftPadding, y, 0, 100, 50)
    y = y + spacing
    
    -- Outline Toggle
    uiInstance.controls.outline = {
        type = "checkbox",
        label = "Add Outline",
        x = leftPadding, y = y,
        checked = true
    }
    y = y + spacing
    
    -- Frame Count Slider
    uiInstance.sliders.frameCount = self:createSlider("Frame Count", leftPadding, y, 2, 8, 4)
    y = y + spacing
    
    -- Animation Speed Slider
    uiInstance.sliders.animationSpeed = self:createSlider("Anim Speed", leftPadding, y, 0.05, 0.5, 0.1)
    y = y + spacing
    
    -- Style Dropdown
    uiInstance.controls.style = {
        type = "dropdown",
        label = "Style",
        x = leftPadding, y = y,
        width = controlWidth,
        options = {"organic", "blocky", "geometric"},
        selected = 1
    }
    y = y + spacing + 10
    
    -- Buttons with improved styling
    local buttonY = love.graphics.getHeight() - 220
    uiInstance.buttons.generate = {
        label = "Generate [SPACE]",
        x = leftPadding, y = buttonY,
        width = 115, height = 35,
        color = COLORS.accent,
        action = function() ui:generateNewSprite() end
    }
    
    uiInstance.buttons.randomize = {
        label = "Randomize [R]",
        x = leftPadding + 125, y = buttonY,
        width = 115, height = 35,
        color = COLORS.warning,
        action = function() ui:randomizeSettings() end
    }
    buttonY = buttonY + 45
    
    uiInstance.buttons.save = {
        label = "Save Sprite [S]",
        x = leftPadding, y = buttonY,
        width = 115, height = 35,
        color = COLORS.success,
        action = function() ui:saveSprite() end
    }
    
    uiInstance.buttons.saveSheet = {
        label = "Save Sheet [A]",
        x = leftPadding + 125, y = buttonY,
        width = 115, height = 35,
        color = COLORS.success,
        action = function() ui:saveSpriteSheet() end
    }
    buttonY = buttonY + 45
    
    uiInstance.buttons.batch = {
        label = "Batch Generate [ENTER]",
        x = leftPadding, y = buttonY,
        width = controlWidth, height = 35,
        color = COLORS.accentDark,
        action = function() ui:batchGenerate() end
    }
end

function UIManager:createSlider(label, x, y, min, max, default)
    return {
        type = "slider",
        label = label,
        x = x, y = y,
        width = 240,
        min = min, max = max,
        value = default,
        percentage = (default - min) / (max - min)
    }
end

function UIManager:draw()
    -- Background
    love.graphics.setColor(COLORS.bg)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Draw left panel
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.left.x, self.panels.left.y, 
                          self.panels.left.width, self.panels.left.height)
    
    -- Panel separator
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.left.width - 1, 0, 1, love.graphics.getHeight())
    
    -- Title
    love.graphics.setFont(self.fonts.title)
    love.graphics.setColor(COLORS.accent)
    love.graphics.print(self.title.text, self.title.x, self.title.y)
    
    -- Draw controls
    love.graphics.setFont(self.fonts.regular)
    
    -- Draw sliders
    for name, slider in pairs(self.sliders) do
        self:drawSlider(slider)
    end
    
    -- Draw other controls
    for name, control in pairs(self.controls) do
        if control.type == "dropdown" then
            self:drawDropdown(control)
        elseif control.type == "checkbox" then
            self:drawCheckbox(control)
        elseif control.type == "input" then
            self:drawInput(control)
        end
    end
    
    -- Draw buttons
    for name, button in pairs(self.buttons) do
        self:drawButton(button)
    end
    
    -- Draw center panel (preview area)
    love.graphics.setColor(COLORS.panelLight)
    love.graphics.rectangle("fill", self.panels.center.x, self.panels.center.y,
                          self.panels.center.width, self.panels.center.height)
    
    -- Draw sprite preview
    if currentSprite then
        self:drawSpritePreview()
    else
        -- Draw placeholder
        love.graphics.setFont(self.fonts.large)
        love.graphics.setColor(COLORS.textDim)
        local text = "Press SPACE to generate a sprite"
        local textWidth = self.fonts.large:getWidth(text)
        love.graphics.print(text, 
            self.panels.center.x + (self.panels.center.width - textWidth) / 2,
            self.panels.center.y + self.panels.center.height / 2)
    end
    
    -- Draw right panel (gallery)
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.right.x, self.panels.right.y,
                          self.panels.right.width, self.panels.right.height)
    
    -- Panel separator
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.right.x, 0, 1, love.graphics.getHeight())
    
    -- Draw sprite history
    self:drawSpriteHistory()
    
    -- Draw bottom panel (timeline)
    love.graphics.setColor(COLORS.panel)
    love.graphics.rectangle("fill", self.panels.bottom.x, self.panels.bottom.y,
                          self.panels.bottom.width, self.panels.bottom.height)
    
    -- Panel separator
    love.graphics.setColor(COLORS.accent[1] * 0.3, COLORS.accent[2] * 0.3, COLORS.accent[3] * 0.3)
    love.graphics.rectangle("fill", self.panels.bottom.x, self.panels.bottom.y, 
                          self.panels.bottom.width, 1)
    
    -- Draw timeline
    self:drawTimeline()
end

function UIManager:drawSlider(slider)
    -- Label
    love.graphics.setColor(COLORS.text)
    love.graphics.print(slider.label, slider.x, slider.y)
    
    -- Track background
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(slider.x, slider.y + 18, slider.width, 6, 3)
    
    -- Track fill
    love.graphics.setColor(COLORS.accentDark)
    Utils.drawRoundedRect(slider.x, slider.y + 18, slider.width * slider.percentage, 6, 3)
    
    -- Handle
    local handleX = slider.x + slider.percentage * slider.width
    if slider == self.activeControl then
        love.graphics.setColor(COLORS.accent)
        love.graphics.circle("fill", handleX, slider.y + 21, 10)
    else
        love.graphics.setColor(COLORS.accent)
        love.graphics.circle("fill", handleX, slider.y + 21, 8)
    end
    
    -- Value
    love.graphics.setColor(COLORS.text)
    local value = slider.value
    if slider.max <= 1 then
        value = string.format("%.2f", value)
    else
        value = string.format("%d", value)
    end
    love.graphics.setFont(self.fonts.small)
    local valueWidth = self.fonts.small:getWidth(value)
    love.graphics.print(value, slider.x + slider.width - valueWidth, slider.y)
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawDropdown(dropdown)
    -- Label
    love.graphics.setColor(COLORS.text)
    love.graphics.print(dropdown.label, dropdown.x, dropdown.y)
    
    -- Box
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(dropdown.x, dropdown.y + 18, dropdown.width, 24, 4)
    
    -- Hover effect
    if dropdown.hovered then
        love.graphics.setColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.1)
        Utils.drawRoundedRect(dropdown.x, dropdown.y + 18, dropdown.width, 24, 4)
    end
    
    -- Selected option
    love.graphics.setColor(COLORS.text)
    love.graphics.print(dropdown.options[dropdown.selected], dropdown.x + 8, dropdown.y + 22)
    
    -- Arrow
    love.graphics.setColor(COLORS.textDim)
    love.graphics.print("▼", dropdown.x + dropdown.width - 20, dropdown.y + 22)
end

function UIManager:drawCheckbox(checkbox)
    -- Box
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(checkbox.x, checkbox.y, 20, 20, 4)
    
    -- Check
    if checkbox.checked then
        love.graphics.setColor(COLORS.accent)
        love.graphics.setLineWidth(3)
        love.graphics.line(checkbox.x + 5, checkbox.y + 10, 
                         checkbox.x + 8, checkbox.y + 14,
                         checkbox.x + 15, checkbox.y + 6)
        love.graphics.setLineWidth(1)
    end
    
    -- Label
    love.graphics.setColor(COLORS.text)
    love.graphics.print(checkbox.label, checkbox.x + 28, checkbox.y + 2)
end

function UIManager:drawInput(input)
    -- Label
    love.graphics.setColor(COLORS.text)
    love.graphics.print(input.label, input.x, input.y)
    
    -- Box
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(input.x, input.y + 18, input.width, 24, 4)
    
    -- Value
    love.graphics.setColor(COLORS.text)
    love.graphics.print(input.value, input.x + 8, input.y + 22)
end

function UIManager:drawButton(button)
    -- Box with color
    local color = button.color or COLORS.accent
    if button.hovered then
        love.graphics.setColor(color[1] * 1.2, color[2] * 1.2, color[3] * 1.2)
    else
        love.graphics.setColor(color)
    end
    Utils.drawRoundedRect(button.x, button.y, button.width, button.height, 6)
    
    -- Label
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.setFont(self.fonts.medium)
    local textWidth = self.fonts.medium:getWidth(button.label)
    local textHeight = self.fonts.medium:getHeight()
    love.graphics.print(button.label, 
        button.x + (button.width - textWidth) / 2,
        button.y + (button.height - textHeight) / 2)
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawSpritePreview()
    local sprite = animation:getCurrentFrame() or currentSprite
    if not sprite then return end
    
    local size = #sprite
    local maxScale = math.floor(math.min(self.panels.center.width * 0.8 / size, 
                                       self.panels.center.height * 0.8 / size))
    local scale = math.min(maxScale, 16)
    
    local startX = self.panels.center.x + (self.panels.center.width - size * scale) / 2
    local startY = self.panels.center.y + (self.panels.center.height - size * scale) / 2
    
    -- Background
    love.graphics.setColor(0.05, 0.05, 0.08)
    Utils.drawRoundedRect(startX - 10, startY - 10, size * scale + 20, size * scale + 20, 8)
    
    -- Draw grid
    love.graphics.setColor(COLORS.grid)
    love.graphics.setLineWidth(1)
    for y = 0, size do
        love.graphics.line(startX, startY + y * scale, startX + size * scale, startY + y * scale)
    end
    for x = 0, size do
        love.graphics.line(startX + x * scale, startY, startX + x * scale, startY + size * scale)
    end
    
    -- Draw sprite
    for y = 1, size do
        for x = 1, size do
            local pixel = sprite[y][x]
            if pixel[4] > 0 then
                love.graphics.setColor(pixel[1], pixel[2], pixel[3], pixel[4])
                love.graphics.rectangle("fill", 
                    startX + (x - 1) * scale, 
                    startY + (y - 1) * scale, 
                    scale, scale)
            end
        end
    end
    
    -- Animation info
    love.graphics.setFont(self.fonts.medium)
    love.graphics.setColor(COLORS.text)
    local animText = string.upper(animation.currentAnimation)
    love.graphics.print(animText, self.panels.center.x + 20, self.panels.center.y + 20)
    
    love.graphics.setFont(self.fonts.small)
    love.graphics.setColor(COLORS.textDim)
    love.graphics.print("Frame " .. animation.currentFrame .. "/" .. 
                       (animation.animations[animation.currentAnimation] and 
                        animation.animations[animation.currentAnimation].frameCount or 1),
                       self.panels.center.x + 20, self.panels.center.y + 40)
    
    -- Size info
    love.graphics.print(size .. "x" .. size .. " pixels", 
                       self.panels.center.x + 20, self.panels.center.y + 55)
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
    for i, sprite in ipairs(spriteHistory) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local x = self.panels.right.x + 20 + col * (thumbSize + spacing)
        local thumbY = y + row * (thumbSize + spacing)
        
        -- Draw thumbnail background
        love.graphics.setColor(COLORS.panelLight)
        Utils.drawRoundedRect(x - 2, thumbY - 2, thumbSize + 4, thumbSize + 4, 4)
        
        -- Hover effect
        local mx, my = love.mouse.getPosition()
        if mx >= x and mx <= x + thumbSize and my >= thumbY and my <= thumbY + thumbSize then
            love.graphics.setColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.2)
            Utils.drawRoundedRect(x - 2, thumbY - 2, thumbSize + 4, thumbSize + 4, 4)
        end
        
        -- Draw sprite thumbnail
        self:drawSpriteThumbnail(sprite, x, thumbY, thumbSize)
        
        -- Number
        love.graphics.setColor(COLORS.textDim)
        love.graphics.print("#" .. i, x + 2, thumbY + thumbSize - 12)
    end
    love.graphics.setFont(self.fonts.regular)
end

function UIManager:drawSpriteThumbnail(sprite, x, y, size)
    local spriteSize = #sprite
    local scale = size / spriteSize
    
    for py = 1, spriteSize do
        for px = 1, spriteSize do
            local pixel = sprite[py][px]
            if pixel[4] > 0 then
                love.graphics.setColor(pixel[1], pixel[2], pixel[3], pixel[4])
                love.graphics.rectangle("fill",
                    x + (px - 1) * scale,
                    y + (py - 1) * scale,
                    scale, scale)
            end
        end
    end
end

function UIManager:drawTimeline()
    love.graphics.setFont(self.fonts.medium)
    love.graphics.setColor(COLORS.text)
    love.graphics.print("ANIMATION TIMELINE", self.panels.bottom.x + 20, self.panels.bottom.y + 10)
    
    -- Animation type buttons
    local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
    local buttonWidth = 80
    local buttonHeight = 25
    local buttonY = self.panels.bottom.y + 35
    
    for i, animType in ipairs(animTypes) do
        local buttonX = self.panels.bottom.x + 20 + (i - 1) * (buttonWidth + 5)
        
        if animation.currentAnimation == animType then
            love.graphics.setColor(COLORS.accent)
        else
            love.graphics.setColor(COLORS.panelLight)
        end
        
        Utils.drawRoundedRect(buttonX, buttonY, buttonWidth, buttonHeight, 4)
        
        love.graphics.setColor(animation.currentAnimation == animType and {0.1, 0.1, 0.1} or COLORS.text)
        love.graphics.setFont(self.fonts.small)
        local textWidth = self.fonts.small:getWidth(animType:upper())
        love.graphics.print(animType:upper(), buttonX + (buttonWidth - textWidth) / 2, buttonY + 6)
    end
    
    -- Draw timeline track
    local trackX = self.panels.bottom.x + 20
    local trackY = self.panels.bottom.y + 70
    local trackWidth = self.panels.bottom.width - 120
    local trackHeight = 30
    
    love.graphics.setColor(COLORS.panelLight)
    Utils.drawRoundedRect(trackX, trackY, trackWidth, trackHeight, 4)
    
    -- Draw frames
    local anim = animation.animations[animation.currentAnimation]
    if anim then
        local frameWidth = trackWidth / anim.frameCount
        
        for i = 1, anim.frameCount do
            -- Frame box
            if i == animation.currentFrame then
                love.graphics.setColor(COLORS.accent)
            else
                love.graphics.setColor(COLORS.grid)
            end
            
            Utils.drawRoundedRect(trackX + (i - 1) * frameWidth + 2,
                trackY + 2,
                frameWidth - 4,
                trackHeight - 4,
                2)
            
            -- Frame number
            love.graphics.setColor(i == animation.currentFrame and {0.1, 0.1, 0.1} or COLORS.text)
            love.graphics.setFont(self.fonts.regular)
            local frameText = tostring(i)
            local textWidth = self.fonts.regular:getWidth(frameText)
            love.graphics.print(frameText, 
                trackX + (i - 1) * frameWidth + frameWidth/2 - textWidth/2,
                trackY + 8)
        end
    end
    
    -- Play/Pause button
    local playButton = {
        x = trackX + trackWidth + 10,
        y = trackY,
        width = 70,
        height = trackHeight
    }
    
    love.graphics.setColor(animation.isPlaying and COLORS.warning or COLORS.success)
    Utils.drawRoundedRect(playButton.x, playButton.y, playButton.width, playButton.height, 4)
    
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.setFont(self.fonts.regular)
    local playText = animation.isPlaying and "PAUSE" or "PLAY"
    local textWidth = self.fonts.regular:getWidth(playText)
    love.graphics.print(playText, 
                       playButton.x + (playButton.width - textWidth) / 2, 
                       playButton.y + 8)
end

function UIManager:updateSettings()
    settings.spriteType = self.controls.spriteType.options[self.controls.spriteType.selected]
    settings.size = math.floor(self.sliders.size.value)
    settings.paletteType = self.controls.paletteType.options[self.controls.paletteType.selected]
    settings.complexity = self.sliders.complexity.value
    settings.symmetry = self.controls.symmetry.options[self.controls.symmetry.selected]
    settings.roughness = self.sliders.roughness.value
    settings.colorCount = math.floor(self.sliders.colorCount.value)
    settings.seed = tonumber(self.controls.seed.value) or os.time()
    settings.anatomyScale = self.sliders.anatomyScale.value
    settings.class = self.controls.class.options[self.controls.class.selected]
    settings.detailLevel = self.sliders.detailLevel.value
    settings.outline = self.controls.outline.checked
    settings.frameCount = math.floor(self.sliders.frameCount.value)
    settings.animationSpeed = self.sliders.animationSpeed.value
    settings.style = self.controls.style.options[self.controls.style.selected]
    
    -- Update palette
    palette.currentPalette = settings.paletteType
end

function UIManager:generateNewSprite()
    self:updateSettings()
    currentSprite = generator:generate(settings)
    
    -- Add to history
    table.insert(spriteHistory, 1, currentSprite)
    if #spriteHistory > maxHistory then
        table.remove(spriteHistory)
    end
    
    -- Generate animations
    local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
    for _, animType in ipairs(animTypes) do
        animation:createAnimation(animType, currentSprite, settings.frameCount, settings)
    end
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
    
    self.controls.spriteType.selected = math.random(1, #self.controls.spriteType.options)
    self.controls.paletteType.selected = math.random(1, #self.controls.paletteType.options)
    self.controls.symmetry.selected = math.random(1, #self.controls.symmetry.options)
    self.controls.class.selected = math.random(1, #self.controls.class.options)
    self.controls.style.selected = math.random(1, #self.controls.style.options)
    self.controls.outline.checked = math.random() > 0.5
    self.controls.seed.value = tostring(os.time() + math.random(1000))
    
    -- Update slider percentages
    for name, slider in pairs(self.sliders) do
        slider.percentage = (slider.value - slider.min) / (slider.max - slider.min)
    end
end

function UIManager:saveSprite()
    if currentSprite then
        export:saveSprite(currentSprite, "sprite_" .. os.time() .. ".png")
    end
end

function UIManager:saveSpriteSheet()
    if animation.animations[animation.currentAnimation] then
        export:saveSpriteSheet(animation.animations[animation.currentAnimation], 
                             "spritesheet_" .. os.time() .. ".png")
    end
end

function UIManager:batchGenerate()
    for i = 1, 10 do
        self:randomizeSettings()
        self:generateNewSprite()
    end
end

function UIManager:mousepressed(x, y, button)
    if button == 1 then
        -- Check sliders
        for name, slider in pairs(self.sliders) do
            if self:isPointInSlider(x, y, slider) then
                self.activeControl = slider
                self:updateSliderValue(slider, x)
            end
        end
        
        -- Check buttons
        for name, btn in pairs(self.buttons) do
            if self:isPointInRect(x, y, btn.x, btn.y, btn.width, btn.height) then
                btn.action()
            end
        end
        
        -- Check dropdowns
        for name, dropdown in pairs(self.controls) do
            if dropdown.type == "dropdown" and 
               self:isPointInRect(x, y, dropdown.x, dropdown.y + 18, dropdown.width, 24) then
                dropdown.selected = dropdown.selected % #dropdown.options + 1
            end
        end
        
        -- Check checkboxes
        for name, checkbox in pairs(self.controls) do
            if checkbox.type == "checkbox" and
               self:isPointInRect(x, y, checkbox.x, checkbox.y, 20, 20) then
                checkbox.checked = not checkbox.checked
            end
        end
        
        -- Check animation type buttons
        local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
        local buttonWidth = 80
        local buttonHeight = 25
        local buttonY = self.panels.bottom.y + 35
        
        for i, animType in ipairs(animTypes) do
            local buttonX = self.panels.bottom.x + 20 + (i - 1) * (buttonWidth + 5)
            if self:isPointInRect(x, y, buttonX, buttonY, buttonWidth, buttonHeight) then
                animation:setAnimation(animType)
            end
        end
        
        -- Check timeline play/pause
        local trackWidth = self.panels.bottom.width - 120
        local playButton = {
            x = self.panels.bottom.x + 20 + trackWidth + 10,
            y = self.panels.bottom.y + 70,
            width = 70,
            height = 30
        }
        if self:isPointInRect(x, y, playButton.x, playButton.y, playButton.width, playButton.height) then
            animation.isPlaying = not animation.isPlaying
        end
        
        -- Check sprite history
        self:checkSpriteHistoryClick(x, y)
    end
end

function UIManager:mousereleased(x, y, button)
    if button == 1 then
        self.activeControl = nil
    end
end

function UIManager:mousemoved(x, y)
    -- Update active slider
    if self.activeControl and self.activeControl.type == "slider" then
        self:updateSliderValue(self.activeControl, x)
    end
    
    -- Update button hover states
    for name, btn in pairs(self.buttons) do
        btn.hovered = self:isPointInRect(x, y, btn.x, btn.y, btn.width, btn.height)
    end
    
    -- Update dropdown hover states
    for name, dropdown in pairs(self.controls) do
        if dropdown.type == "dropdown" then
            dropdown.hovered = self:isPointInRect(x, y, dropdown.x, dropdown.y + 18, dropdown.width, 24)
        end
    end
end

function UIManager:isPointInRect(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function UIManager:isPointInSlider(px, py, slider)
    return self:isPointInRect(px, py, slider.x - 10, slider.y + 10, slider.width + 20, 20)
end

function UIManager:updateSliderValue(slider, x)
    slider.percentage = Utils.clamp((x - slider.x) / slider.width, 0, 1)
    slider.value = slider.min + (slider.max - slider.min) * slider.percentage
end

function UIManager:checkSpriteHistoryClick(x, y)
    local thumbSize = 72
    local spacing = 12
    local startY = 55
    local columns = 3
    
    for i, sprite in ipairs(spriteHistory) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local thumbX = self.panels.right.x + 20 + col * (thumbSize + spacing)
        local thumbY = startY + row * (thumbSize + spacing)
        
        if self:isPointInRect(x, y, thumbX, thumbY, thumbSize, thumbSize) then
            currentSprite = sprite
            -- Regenerate animations for this sprite
            local animTypes = {"idle", "walk_right", "walk_left", "attack", "hurt", "death"}
            for _, animType in ipairs(animTypes) do
                animation:createAnimation(animType, currentSprite, settings.frameCount, settings)
            end
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
            local pixel = sprite[y][x]
            imageData:setPixel(x - 1, y - 1, pixel[1], pixel[2], pixel[3], pixel[4])
        end
    end
    
    imageData:encode("png", filename)
    print("Saved sprite to: " .. filename)
end

function ExportManager:saveSpriteSheet(animation, filename)
    local frames = animation.frames
    local frameCount = animation.frameCount
    local size = #frames[1]
    
    local sheetWidth = size * frameCount
    local imageData = love.image.newImageData(sheetWidth, size)
    
    for i, frame in ipairs(frames) do
        local offsetX = (i - 1) * size
        
        for y = 1, size do
            for x = 1, size do
                local pixel = frame[y][x]
                imageData:setPixel(offsetX + x - 1, y - 1, pixel[1], pixel[2], pixel[3], pixel[4])
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

function PresetManager:savePreset(slot, settings)
    self.presets[slot] = Utils.deepCopy(settings)
    print("Saved preset to slot " .. slot)
end

function PresetManager:loadPreset(slot)
    if self.presets[slot] then
        return Utils.deepCopy(self.presets[slot])
    end
    return nil
end

-- ==============================================
-- MAIN LÖVE2D FUNCTIONS
-- ==============================================
function love.load()
    love.window.setTitle("Pixel Art Sprite Generator")
    love.window.setMode(1280, 800, {resizable = false})
    
    -- Initialize modules
    generator = SpriteGenerator:new()
    animation = AnimationSystem:new()
    ui = UIManager:new()
    palette = PaletteManager:new()
    export = ExportManager:new()
    preset = PresetManager:new()
    
    -- Copy default settings
    for k, v in pairs(DEFAULT_SETTINGS) do
        settings[k] = v
    end
    
    -- Generate initial sprite
    ui:generateNewSprite()
end

function love.update(dt)
    animation:update(dt)
end

function love.draw()
    ui:draw()
end

function love.mousepressed(x, y, button)
    ui:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    ui:mousereleased(x, y, button)
end

function love.mousemoved(x, y)
    ui:mousemoved(x, y)
end

function love.keypressed(key)
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
        -- Cycle sprite type
        local dropdown = ui.controls.spriteType
        dropdown.selected = dropdown.selected % #dropdown.options + 1
    elseif tonumber(key) and tonumber(key) >= 1 and tonumber(key) <= 9 then
        if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
            -- Save preset
            preset:savePreset(tonumber(key), settings)
        else
            -- Load preset
            local loadedSettings = preset:loadPreset(tonumber(key))
            if loadedSettings then
                settings = loadedSettings
                -- Update UI to reflect loaded settings
                -- This would require a more complex implementation
                print("Loaded preset " .. key)
            end
        end
    end
end