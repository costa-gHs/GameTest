-- gen.lua - Gerador de Mundo Procedural
-- Sistema híbrido BSP + Room-Corridor para gerar mapas de rogue-lite

local WorldGenerator = {}
local RNG = require("src.core.rng")
local EventBus = require("src.core.eventbus")

-- Tipos de tile
local TileType = {
    VOID = 0,
    FLOOR = 1,
    WALL = 2,
    DOOR = 3,
    SPAWN = 4,
    EXIT = 5,
    TREASURE = 6
}

-- Configurações de geração
local GenConfig = {
    MAP_SIZE = 128,
    MIN_ROOM_SIZE = 8,
    MAX_ROOM_SIZE = 20,
    MIN_ROOMS = 5,
    MAX_ROOMS = 12,
    CORRIDOR_WIDTH = 3,
    BIOME_CHANGE_CHANCE = 0.3
}

function WorldGenerator:new(config)
    local wg = {}
    setmetatable(wg, { __index = self })
    
    wg.config = config
    wg.seed = config.seed
    wg.currentLevel = 1
    wg.currentBiome = config.biomes[1] or "floresta_temperada"
    
    -- Dados do mundo atual
    wg.map = {}
    wg.rooms = {}
    wg.corridors = {}
    wg.spawners = {}
    wg.treasures = {}
    wg.exits = {}
    
    -- Configurações de bioma
    wg.biomes = {
        floresta_temperada = {
            name = "Floresta Temperada",
            wallColor = {0.2, 0.5, 0.2},
            floorColor = {0.3, 0.7, 0.3},
            enemyTypes = {"wanderer", "guard"},
            enemyDensity = 0.02,
            treasureDensity = 0.01,
            music = "forest_ambient"
        },
        pantano_tempestuoso = {
            name = "Pântano Tempestuoso", 
            wallColor = {0.3, 0.4, 0.2},
            floorColor = {0.4, 0.5, 0.3},
            enemyTypes = {"hunter", "mage"},
            enemyDensity = 0.03,
            treasureDensity = 0.015,
            music = "swamp_storm"
        },
        cavernas_de_cristal = {
            name = "Cavernas de Cristal",
            wallColor = {0.4, 0.3, 0.6},
            floorColor = {0.5, 0.4, 0.7},
            enemyTypes = {"guardian", "crystal_beast"},
            enemyDensity = 0.025,
            treasureDensity = 0.02,
            music = "crystal_caves"
        }
    }
    
    return wg
end

function WorldGenerator:generate()
    RNG:setSeed(self.seed + self.currentLevel * 1000)
    
    print("Gerando mundo - Nível: " .. self.currentLevel .. ", Bioma: " .. self.currentBiome)
    
    -- Inicializar mapa vazio
    self:initializeMap()
    
    -- Gerar salas usando BSP
    local rootNode = self:generateBSP()
    
    -- Conectar salas com corredores
    self:connectRooms()
    
    -- Adicionar paredes ao redor de pisos
    self:addWalls()
    
    -- Colocar spawn e saída
    self:placeSpawnAndExit()
    
    -- Popular com inimigos e tesouros
    self:populateWorld()
    
    -- Emitir evento de mundo gerado
    EventBus:emit("world:generated", {
        level = self.currentLevel,
        biome = self.currentBiome,
        rooms = #self.rooms,
        seed = self.seed
    })
    
    print("Mundo gerado: " .. #self.rooms .. " salas, " .. #self.spawners .. " inimigos")
end

function WorldGenerator:initializeMap()
    self.map = {}
    for y = 1, GenConfig.MAP_SIZE do
        self.map[y] = {}
        for x = 1, GenConfig.MAP_SIZE do
            self.map[y][x] = TileType.VOID
        end
    end
    
    self.rooms = {}
    self.corridors = {}
    self.spawners = {}
    self.treasures = {}
    self.exits = {}
end

-- BSP (Binary Space Partitioning) para gerar salas
function WorldGenerator:generateBSP()
    local root = {
        x = 5,
        y = 5, 
        width = GenConfig.MAP_SIZE - 10,
        height = GenConfig.MAP_SIZE - 10,
        level = 0
    }
    
    self:splitNode(root)
    self:createRoomsFromLeaves(root)
    
    return root
end

function WorldGenerator:splitNode(node)
    if node.level >= 4 then return end -- Máximo 4 níveis de divisão
    
    local minSize = GenConfig.MIN_ROOM_SIZE * 2 + 4
    if node.width < minSize and node.height < minSize then return end
    
    -- Decidir direção do corte
    local splitVertical = false
    if node.width > node.height * 1.25 then
        splitVertical = true
    elseif node.height > node.width * 1.25 then
        splitVertical = false
    else
        splitVertical = RNG:randomBool()
    end
    
    local splitPos
    if splitVertical then
        splitPos = RNG:randomInt(node.x + minSize/2, node.x + node.width - minSize/2)
        
        node.child1 = {
            x = node.x,
            y = node.y,
            width = splitPos - node.x,
            height = node.height,
            level = node.level + 1,
            parent = node
        }
        
        node.child2 = {
            x = splitPos,
            y = node.y,
            width = node.x + node.width - splitPos,
            height = node.height,
            level = node.level + 1,
            parent = node
        }
    else
        splitPos = RNG:randomInt(node.y + minSize/2, node.y + node.height - minSize/2)
        
        node.child1 = {
            x = node.x,
            y = node.y,
            width = node.width,
            height = splitPos - node.y,
            level = node.level + 1,
            parent = node
        }
        
        node.child2 = {
            x = node.x,
            y = splitPos,
            width = node.width,
            height = node.y + node.height - splitPos,
            level = node.level + 1,
            parent = node
        }
    end
    
    -- Continuar dividindo
    self:splitNode(node.child1)
    self:splitNode(node.child2)
end

function WorldGenerator:createRoomsFromLeaves(node)
    if node.child1 and node.child2 then
        -- Nó interno - processar filhos
        self:createRoomsFromLeaves(node.child1)
        self:createRoomsFromLeaves(node.child2)
    else
        -- Folha - criar sala
        local room = self:createRoomInNode(node)
        if room then
            table.insert(self.rooms, room)
            node.room = room
        end
    end
end

function WorldGenerator:createRoomInNode(node)
    local margin = 2
    local maxWidth = math.min(GenConfig.MAX_ROOM_SIZE, node.width - margin * 2)
    local maxHeight = math.min(GenConfig.MAX_ROOM_SIZE, node.height - margin * 2)
    
    if maxWidth < GenConfig.MIN_ROOM_SIZE or maxHeight < GenConfig.MIN_ROOM_SIZE then
        return nil
    end
    
    local roomWidth = RNG:randomInt(GenConfig.MIN_ROOM_SIZE, maxWidth)
    local roomHeight = RNG:randomInt(GenConfig.MIN_ROOM_SIZE, maxHeight)
    
    local roomX = node.x + RNG:randomInt(margin, node.width - roomWidth - margin)
    local roomY = node.y + RNG:randomInt(margin, node.height - roomHeight - margin)
    
    local room = {
        x = roomX,
        y = roomY,
        width = roomWidth,
        height = roomHeight,
        centerX = roomX + math.floor(roomWidth / 2),
        centerY = roomY + math.floor(roomHeight / 2),
        connections = {},
        type = "normal"
    }
    
    -- Preencher sala no mapa
    for y = roomY, roomY + roomHeight - 1 do
        for x = roomX, roomX + roomWidth - 1 do
            if self:isValidCoord(x, y) then
                self.map[y][x] = TileType.FLOOR
            end
        end
    end
    
    return room
end

function WorldGenerator:connectRooms()
    if #self.rooms < 2 then return end
    
    -- Conectar salas em sequência (garantir conectividade)
    for i = 1, #self.rooms - 1 do
        local roomA = self.rooms[i]
        local roomB = self.rooms[i + 1]
        self:createCorridor(roomA, roomB)
    end
    
    -- Adicionar algumas conexões extras para loops
    local extraConnections = math.min(3, math.floor(#self.rooms / 3))
    for i = 1, extraConnections do
        local roomA = self.rooms[RNG:randomInt(1, #self.rooms)]
        local roomB = self.rooms[RNG:randomInt(1, #self.rooms)]
        
        if roomA ~= roomB then
            self:createCorridor(roomA, roomB)
        end
    end
end

function WorldGenerator:createCorridor(roomA, roomB)
    local startX, startY = roomA.centerX, roomA.centerY
    local endX, endY = roomB.centerX, roomB.centerY
    
    -- Corredor em L (horizontal primeiro, depois vertical)
    local corridor = {
        points = {},
        rooms = {roomA, roomB}
    }
    
    -- Horizontal
    local minX, maxX = math.min(startX, endX), math.max(startX, endX)
    for x = minX, maxX do
        self:digCorridorTile(x, startY)
        table.insert(corridor.points, {x = x, y = startY})
    end
    
    -- Vertical
    local minY, maxY = math.min(startY, endY), math.max(startY, endY)
    for y = minY, maxY do
        self:digCorridorTile(endX, y)
        table.insert(corridor.points, {x = endX, y = y})
    end
    
    table.insert(self.corridors, corridor)
    table.insert(roomA.connections, roomB)
    table.insert(roomB.connections, roomA)
end

function WorldGenerator:digCorridorTile(x, y)
    local width = GenConfig.CORRIDOR_WIDTH
    local halfWidth = math.floor(width / 2)
    
    for dy = -halfWidth, halfWidth do
        for dx = -halfWidth, halfWidth do
            local tx, ty = x + dx, y + dy
            if self:isValidCoord(tx, ty) then
                if self.map[ty][tx] == TileType.VOID then
                    self.map[ty][tx] = TileType.FLOOR
                end
            end
        end
    end
end

function WorldGenerator:addWalls()
    local tempMap = {}
    for y = 1, GenConfig.MAP_SIZE do
        tempMap[y] = {}
        for x = 1, GenConfig.MAP_SIZE do
            tempMap[y][x] = self.map[y][x]
        end
    end
    
    for y = 1, GenConfig.MAP_SIZE do
        for x = 1, GenConfig.MAP_SIZE do
            if self.map[y][x] == TileType.FLOOR then
                -- Verificar vizinhos
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nx, ny = x + dx, y + dy
                        if self:isValidCoord(nx, ny) then
                            if self.map[ny][nx] == TileType.VOID then
                                tempMap[ny][nx] = TileType.WALL
                            end
                        end
                    end
                end
            end
        end
    end
    
    self.map = tempMap
end

function WorldGenerator:placeSpawnAndExit()
    if #self.rooms < 2 then return end
    
    -- Spawn na primeira sala
    local spawnRoom = self.rooms[1]
    spawnRoom.type = "spawn"
    self.map[spawnRoom.centerY][spawnRoom.centerX] = TileType.SPAWN
    
    -- Saída na última sala (mais distante)
    local exitRoom = self.rooms[#self.rooms]
    exitRoom.type = "exit"
    self.map[exitRoom.centerY][exitRoom.centerX] = TileType.EXIT
    
    table.insert(self.exits, {
        x = exitRoom.centerX,
        y = exitRoom.centerY,
        nextLevel = self.currentLevel + 1,
        nextBiome = self:getNextBiome()
    })
end

function WorldGenerator:populateWorld()
    local biome = self.biomes[self.currentBiome]
    if not biome then return end
    
    for _, room in ipairs(self.rooms) do
        if room.type == "normal" then
            -- Spawnar inimigos
            local enemyCount = math.floor(room.width * room.height * biome.enemyDensity)
            for i = 1, enemyCount do
                local x = RNG:randomInt(room.x + 1, room.x + room.width - 2)
                local y = RNG:randomInt(room.y + 1, room.y + room.height - 2)
                
                if self.map[y][x] == TileType.FLOOR then
                    local enemyType = RNG:choice(biome.enemyTypes)
                    table.insert(self.spawners, {
                        x = x,
                        y = y,
                        type = "enemy",
                        subtype = enemyType,
                        biome = self.currentBiome
                    })
                end
            end
            
            -- Spawnar tesouros
            if RNG:randomBool(biome.treasureDensity * 100) then
                local x = RNG:randomInt(room.x + 1, room.x + room.width - 2)
                local y = RNG:randomInt(room.y + 1, room.y + room.height - 2)
                
                if self.map[y][x] == TileType.FLOOR then
                    self.map[y][x] = TileType.TREASURE
                    table.insert(self.treasures, {
                        x = x,
                        y = y,
                        type = "treasure",
                        rarity = self:getTreasureRarity()
                    })
                end
            end
        end
    end
end

function WorldGenerator:getTreasureRarity()
    local roll = RNG:random()
    if roll < 0.6 then return "common"
    elseif roll < 0.85 then return "uncommon"
    elseif roll < 0.95 then return "rare"
    else return "legendary" end
end

function WorldGenerator:getNextBiome()
    local currentIndex = 1
    for i, biomeName in ipairs(self.config.biomes) do
        if biomeName == self.currentBiome then
            currentIndex = i
            break
        end
    end
    
    if RNG:randomBool(GenConfig.BIOME_CHANGE_CHANCE) then
        local nextIndex = (currentIndex % #self.config.biomes) + 1
        return self.config.biomes[nextIndex]
    else
        return self.currentBiome
    end
end

function WorldGenerator:isValidCoord(x, y)
    return x >= 1 and x <= GenConfig.MAP_SIZE and y >= 1 and y <= GenConfig.MAP_SIZE
end

function WorldGenerator:getTileAt(x, y)
    if not self:isValidCoord(x, y) then return TileType.VOID end
    if not self.map or not self.map[y] then return TileType.VOID end
    return self.map[y][x] or TileType.VOID
end

function WorldGenerator:getWorldSpawn()
    for _, room in ipairs(self.rooms) do
        if room.type == "spawn" then
            return room.centerX * 32, room.centerY * 32 -- Converter para pixels
        end
    end
    return 0, 0
end

function WorldGenerator:getCurrentBiome()
    return self.biomes[self.currentBiome]
end

function WorldGenerator:nextLevel()
    self.currentLevel = self.currentLevel + 1
    
    -- Chance de mudar de bioma
    if RNG:randomBool(GenConfig.BIOME_CHANGE_CHANCE) then
        local currentIndex = 1
        for i, biomeName in ipairs(self.config.biomes) do
            if biomeName == self.currentBiome then
                currentIndex = i
                break
            end
        end
        
        local nextIndex = (currentIndex % #self.config.biomes) + 1
        self.currentBiome = self.config.biomes[nextIndex]
        
        print("Mudando para bioma: " .. self.currentBiome)
    end
    
    self:generate()
end

-- Método para desenhar o mundo (debug)
function WorldGenerator:draw()
    local biome = self.biomes[self.currentBiome]
    if not biome then return end
    
    if not self.map then return end
    
    local tileSize = 4 -- Pequeno para ver o mapa todo
    local offsetX = love.graphics.getWidth() - GenConfig.MAP_SIZE * tileSize - 10
    local offsetY = 10
    
    for y = 1, GenConfig.MAP_SIZE do
        for x = 1, GenConfig.MAP_SIZE do
            local tile = self:getTileAt(x, y)
            local screenX = offsetX + (x - 1) * tileSize
            local screenY = offsetY + (y - 1) * tileSize
            
            if tile == TileType.WALL then
                love.graphics.setColor(biome.wallColor)
                love.graphics.rectangle("fill", screenX, screenY, tileSize, tileSize)
            elseif tile == TileType.FLOOR then
                love.graphics.setColor(biome.floorColor)
                love.graphics.rectangle("fill", screenX, screenY, tileSize, tileSize)
            elseif tile == TileType.SPAWN then
                love.graphics.setColor(0, 1, 0) -- Verde
                love.graphics.rectangle("fill", screenX, screenY, tileSize, tileSize)
            elseif tile == TileType.EXIT then
                love.graphics.setColor(1, 0, 0) -- Vermelho
                love.graphics.rectangle("fill", screenX, screenY, tileSize, tileSize)
            elseif tile == TileType.TREASURE then
                love.graphics.setColor(1, 1, 0) -- Amarelo
                love.graphics.rectangle("fill", screenX, screenY, tileSize, tileSize)
            end
        end
    end
    
    love.graphics.setColor(1, 1, 1)
end

function WorldGenerator:update(dt)
    -- Atualizar sistemas do mundo se necessário
end

return WorldGenerator 