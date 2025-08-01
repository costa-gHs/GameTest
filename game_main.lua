-- game_main.lua - Main do jogo SLIME: Tempest Trials
-- Integra todos os sistemas criados com o gerador de sprites existente

-- Importar sistemas do jogo
local App = require("src.core.app")
local EventBus = require("src.core.eventbus")
local ECS = require("src.core.ecs")
local RNG = require("src.core.rng")
local WorldGenerator = require("src.world.gen")
local CombatSystem = require("src.combat.combat")
local SkillSystem = require("src.gameplay.skills")
local UIManager = require("src.render.ui")
local Logger = require("src.core.logger")
local SpriteGenerator = require("sprite_generator")

-- Importar gerador de sprites existente
local SpriteGenerator = require("sprite_module")

-- Instância global da aplicação
local app = nil
local ecs = nil
local world = nil
local combat = nil
local skills = nil
local ui = nil

    -- Camera simples
    local camera = {
        x = 0,
        y = 0,
        scale = 3, -- Aumentar escala para ver melhor
        target = nil
    }

-- Sistemas globais
_G.camera = camera -- Expor globalmente para outros sistemas

-- Cores da UI (para notificações)
local UIColors = {
    success = {0.3, 0.8, 0.3, 1},
    error = {0.9, 0.3, 0.3, 1},
    warning = {0.9, 0.7, 0.2, 1},
    accent = {0.3, 0.7, 0.9, 1},
    mana = {0.5, 0.3, 0.8, 1}
}

-- Função auxiliar para desenhar tiles do mundo
local function drawWorldTiles()
    if not world or not world.map then return end
    
    local tileSize = 32
    local biome = world:getCurrentBiome()
    if not biome then return end
    
    -- Calcular região visível
    local startX = math.max(1, math.floor((camera.x - love.graphics.getWidth() / camera.scale / 2) / tileSize))
    local endX = math.min(128, math.ceil((camera.x + love.graphics.getWidth() / camera.scale / 2) / tileSize))
    local startY = math.max(1, math.floor((camera.y - love.graphics.getHeight() / camera.scale / 2) / tileSize))
    local endY = math.min(128, math.ceil((camera.y + love.graphics.getHeight() / camera.scale / 2) / tileSize))
    
    -- Desenhar apenas tiles visíveis
    for y = startY, endY do
        for x = startX, endX do
            local tile = world:getTileAt(x, y)
            local worldX = x * tileSize
            local worldY = y * tileSize
            
            if tile == 1 then -- FLOOR
                love.graphics.setColor(biome.floorColor)
                love.graphics.rectangle("fill", worldX, worldY, tileSize, tileSize)
            elseif tile == 2 then -- WALL
                love.graphics.setColor(biome.wallColor)
                love.graphics.rectangle("fill", worldX, worldY, tileSize, tileSize)
            elseif tile == 4 then -- SPAWN
                love.graphics.setColor(0, 1, 0) -- Verde
                love.graphics.rectangle("fill", worldX, worldY, tileSize, tileSize)
            elseif tile == 5 then -- EXIT
                love.graphics.setColor(1, 0, 0) -- Vermelho
                love.graphics.rectangle("fill", worldX, worldY, tileSize, tileSize)
            end
        end
    end
end

-- Sistemas ECS do jogo
local function createGameSystems()
    -- Sistema de movimento
    ecs:addSystem("movement", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Velocity")
        
        for _, entity in ipairs(entities) do
            local transform = ecsInstance:getComponent(entity, "Transform")
            local velocity = ecsInstance:getComponent(entity, "Velocity")
            
            -- Aplicar velocidade
            transform.x = transform.x + velocity.vx * dt
            transform.y = transform.y + velocity.vy * dt
            
            -- Aplicar atrito
            velocity.vx = velocity.vx * 0.9
            velocity.vy = velocity.vy * 0.9
            
            -- Seguir slime com câmera
            if ecsInstance:hasComponent(entity, "SlimeCore") then
                camera.x = transform.x
                camera.y = transform.y
            end
        end
    end, 10)
    
    -- Sistema de colisão - CORRIGIDO
    ecs:addSystem("collision", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Collider")
        
        for i = 1, #entities do
            for j = i + 1, #entities do
                local entityA = entities[i]
                local entityB = entities[j]
                
                local transformA = ecsInstance:getComponent(entityA, "Transform")
                local transformB = ecsInstance:getComponent(entityB, "Transform")
                local colliderA = ecsInstance:getComponent(entityA, "Collider")
                local colliderB = ecsInstance:getComponent(entityB, "Collider")
                
                -- Verificar colisão circular simples
                local dx = transformB.x - transformA.x
                local dy = transformB.y - transformA.y
                local distance = math.sqrt(dx * dx + dy * dy)
                local minDistance = colliderA.radius + colliderB.radius
                
                if distance < minDistance and distance > 0 then
                    -- Separar entidades colidindo
                    local overlap = minDistance - distance
                    local separateX = (dx / distance) * (overlap / 2)
                    local separateY = (dy / distance) * (overlap / 2)
                    
                    transformA.x = transformA.x - separateX
                    transformA.y = transformA.y - separateY
                    transformB.x = transformB.x + separateX
                    transformB.y = transformB.y + separateY
                    
                    -- Trigger eventos de colisão se necessário
                    if ecsInstance:hasComponent(entityA, "SlimeCore") and ecsInstance:hasComponent(entityB, "Enemy") then
                        Logger:debug("Slime colidiu com inimigo")
                    end
                end
            end
        end
    end, 11)
    
    -- Sistema de colisão com mundo - CORRIGIDO
    ecs:addSystem("world_collision", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Velocity", "Collider")
        
        for _, entity in ipairs(entities) do
            local transform = ecsInstance:getComponent(entity, "Transform")
            local velocity = ecsInstance:getComponent(entity, "Velocity")
            local collider = ecsInstance:getComponent(entity, "Collider")
            
            -- Calcular nova posição
            local newX = transform.x + velocity.vx * dt
            local newY = transform.y + velocity.vy * dt
            
            -- ✅ USAR FUNÇÃO LOCAL EM VEZ DE self:
            if not checkWorldCollision(newX, transform.y, collider.radius, world) then
                transform.x = newX
            else
                velocity.vx = velocity.vx * -0.3 -- Bounce na parede
            end
            
            if not checkWorldCollision(transform.x, newY, collider.radius, world) then
                transform.y = newY
            else
                velocity.vy = velocity.vy * -0.3 -- Bounce na parede
            end
        end
    end, 12)
end

local function generateSpriteForEntity(entity, entityType)
    local settings = {
        spriteType = entityType == "slime" and "character" or "character",
        size = entityType == "slime" and 16 or 12,
        paletteType = "NES",
        complexity = entityType == "slime" and 60 or 40,
        symmetry = "vertical",
        colorCount = entityType == "slime" and 6 or 4,
        visualSeed = entity.id * 123 + love.timer.getTime(),
        structureSeed = entity.id * 456,
        class = entityType == "slime" and "mage" or "warrior",
        outline = true,
        silhouetteStyle = entityType == "slime" and "chibi" or "heroic"
    }
    
    -- Usar o gerador real
    local spriteData = SpriteGenerator:generate(settings)
    
    if spriteData then
        -- Converter para textura LÖVE 2D
        local size = #spriteData
        local imageData = love.image.newImageData(size, size)
        
        for y = 1, size do
            for x = 1, size do
                local pixel = spriteData[y][x]
                imageData:setPixel(x - 1, y - 1, pixel[1], pixel[2], pixel[3], pixel[4])
            end
        end
        
        return love.graphics.newImage(imageData)
    end
    
    return nil
end

-- Sistema de input do jogador
local function handlePlayerInput(dt)
    local slimes = ecs:getEntitiesWith("SlimeCore", "Transform", "Velocity")
    if #slimes == 0 then return end
    
    local slime = slimes[1]
    local transform = ecs:getComponent(slime, "Transform")
    local velocity = ecs:getComponent(slime, "Velocity")
    
    local speed = 150
    local inputX, inputY = 0, 0
    
    -- Movimento WASD
    if love.keyboard.isDown("w") then inputY = inputY - 1 end
    if love.keyboard.isDown("s") then inputY = inputY + 1 end
    if love.keyboard.isDown("a") then inputX = inputX - 1 end
    if love.keyboard.isDown("d") then inputX = inputX + 1 end
    
    -- Normalizar diagonal
    if inputX ~= 0 and inputY ~= 0 then
        inputX = inputX * 0.707
        inputY = inputY * 0.707
    end
    
    velocity.vx = velocity.vx + inputX * speed * dt * 10
    velocity.vy = velocity.vy + inputY * speed * dt * 10
    
    -- Limitar velocidade máxima
    local maxSpeed = velocity.maxSpeed or 120
    local currentSpeed = math.sqrt(velocity.vx * velocity.vx + velocity.vy * velocity.vy)
    if currentSpeed > maxSpeed then
        velocity.vx = (velocity.vx / currentSpeed) * maxSpeed
        velocity.vy = (velocity.vy / currentSpeed) * maxSpeed
    end
    
    -- Dash com Shift + movimento
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        if inputX ~= 0 or inputY ~= 0 then
            if combat then
                local direction = {x = inputX, y = inputY}
                combat:playerDash(slime, direction, ecs)
            end
        end
    end
    
    -- Ataque com clique direito ou X
    if love.keyboard.isDown("x") then
        if combat then
            combat:playerAttack(slime, ecs)
        end
    end
    
    -- Agarre com C
    if love.keyboard.isDown("c") then
        if combat then
            combat:playerGrab(slime, ecs)
        end
    end
    
    -- Atualizar câmera para seguir o slime
    camera.target = {x = transform.x, y = transform.y}
end

-- Atualizar câmera
local function updateCamera(dt)
    if camera.target then
        -- Suavizar movimento da câmera
        local lerpFactor = 5 * dt
        camera.x = camera.x + (camera.target.x - camera.x) * lerpFactor
        camera.y = camera.y + (camera.target.y - camera.y) * lerpFactor
    end
end

-- Gerar sprites usando o gerador existente
local function generateSpriteForEntity(entity, settings)
    if not SpriteGenerator then return nil end
    
    -- Usar o gerador de sprites
    local spriteData = nil
    if SpriteGenerator and SpriteGenerator.generate then
        spriteData = SpriteGenerator:generate(settings)
    end
    
    -- Converter para textura do Love2D
    if spriteData then
        local size = #spriteData
        local imageData = love.image.newImageData(size, size)
        
        for y = 1, size do
            for x = 1, size do
                local pixel = spriteData[y][x]
                imageData:setPixel(x - 1, y - 1, pixel[1], pixel[2], pixel[3], pixel[4])
            end
        end
        
        local texture = love.graphics.newImage(imageData)
        return texture
    end
    
    return nil
end

-- Spawnar entidades baseado no mundo gerado
local function spawnEntitiesFromWorld()
    if not world then return end
    
    local tileSize = 32
    
    -- Spawnar inimigos dos spawners do mundo
    for _, spawner in ipairs(world.spawners) do
        if spawner.type == "enemy" then
            local worldX = spawner.x * tileSize
            local worldY = spawner.y * tileSize
            
            local enemy = ecs:createEnemy(worldX, worldY, spawner.subtype)
            
            -- Adicionar componente de combate
            ecs:addComponent(enemy, "Combat", {
                state = "idle",
                health = 50,
                maxHealth = 50,
                attackDamage = 15,
                dashCooldownTimer = 0,
                attackCooldownTimer = 0,
                iFramesTimer = 0
            })
            
            -- Gerar sprite para o inimigo
            local enemySettings = {
                spriteType = "character",
                size = 12,
                paletteType = "NES",
                complexity = 30,
                symmetry = "vertical",
                colorCount = 4,
                structureSeed = RNG:randomInt(1, 1000000),
                visualSeed = RNG:randomInt(1, 1000000),
                class = "warrior",
                outline = true
            }
            
            local sprite = ecs:getComponent(enemy, "Sprite")
            sprite.texture = generateSpriteForEntity(enemy, enemySettings)
        end
    end
    
    -- Spawnar tesouros
    for _, treasure in ipairs(world.treasures) do
        local worldX = treasure.x * tileSize
        local worldY = treasure.y * tileSize
        
        ecs:createItem(worldX, worldY, "treasure")
    end
    
    print("Spawnado: " .. #world.spawners .. " inimigos, " .. #world.treasures .. " tesouros")
end

-- Spawnar inimigos aleatórios (para debug)
local function spawnRandomEnemies()
    for i = 1, 5 do
        local x = RNG:randomFloat(-200, 200)
        local y = RNG:randomFloat(-200, 200)
        
        local enemy = ecs:createEnemy(x, y, "wanderer")
        
        -- Adicionar componente de combate
        ecs:addComponent(enemy, "Combat", {
            state = "idle",
            health = 50,
            maxHealth = 50,
            attackDamage = 15,
            dashCooldownTimer = 0,
            attackCooldownTimer = 0,
            iFramesTimer = 0
        })
        
        -- Gerar sprite para o inimigo
        local enemySettings = {
            spriteType = "character",
            size = 12,
            paletteType = "NES",
            complexity = 30,
            symmetry = "vertical",
            colorCount = 4,
            structureSeed = RNG:randomInt(1, 1000000),
            visualSeed = RNG:randomInt(1, 1000000),
            class = "warrior",
            outline = true
        }
        
        local sprite = ecs:getComponent(enemy, "Sprite")
        sprite.texture = generateSpriteForEntity(enemy, enemySettings)
    end
end

-- Callbacks do Love2D
function love.load()
    -- Inicializar logger
    Logger:clear()
    Logger:info("=== INICIANDO SLIME: TEMPEST TRIALS ===")
    Logger:info("Versão: 1.0.0")
    Logger:info("Data/Hora: " .. os.date())
    
    -- Inicializar aplicação
    app = App.getInstance()
    app:initialize()
    Logger:info("Aplicação inicializada")
    
    -- Inicializar sistemas
    ecs = ECS
    world = WorldGenerator:new(app.config)
    combat = CombatSystem:new()
    skills = SkillSystem:new(app.config)
    ui = UIManager:new(app.config)
    Logger:info("Sistemas inicializados")
    
    createGameSystems()
    
    -- Configurar eventos
    EventBus:on("collision:trigger", function(data)
        local entityA = data.entityA
        local entityB = data.entityB
        
        -- Verificar se slime colidiu com item
        if ecs:hasComponent(entityA, "SlimeCore") and ecs:hasComponent(entityB, "Item") then
            -- Coletar item
            local item = ecs:getComponent(entityB, "Item")
            local slimeCore = ecs:getComponent(entityA, "SlimeCore")
            slimeCore.essence = slimeCore.essence + (item.value or 1)
            ecs:removeEntity(entityB)
            print("Essência coletada! Total: " .. slimeCore.essence)
        elseif ecs:hasComponent(entityB, "SlimeCore") and ecs:hasComponent(entityA, "Item") then
            -- Mesmo caso, mas ordem inversa
            local item = ecs:getComponent(entityA, "Item")
            local slimeCore = ecs:getComponent(entityB, "SlimeCore")
            slimeCore.essence = slimeCore.essence + (item.value or 1)
            ecs:removeEntity(entityA)
            print("Essência coletada! Total: " .. slimeCore.essence)
        end
    end)
    
    -- Gerar mundo
    Logger:info("=== GERANDO MUNDO ===")
    world:generate()
    Logger:info("✅ Mundo gerado com sucesso!")
    
    -- Obter posição de spawn do mundo
    local spawnX, spawnY = world:getWorldSpawn()
    Logger:info("📍 Spawn do mundo", {x = spawnX, y = spawnY})
    
    -- Criar slime do jogador na posição de spawn
    Logger:info("🎮 Criando slime do jogador...")
    local slime = ecs:createSlime(spawnX, spawnY)
    Logger:info("✅ Slime criado com sucesso!", {id = slime, x = spawnX, y = spawnY})
    
    -- Adicionar componente de combate ao slime
    ecs:addComponent(slime, "Combat", {
        state = "idle",
        health = 100,
        maxHealth = 100,
        attackDamage = 20,
        dashCooldownTimer = 0,
        attackCooldownTimer = 0,
        iFramesTimer = 0
    })
    
    -- Conectar slime com o controller
    if app.slime then
        app.slime:setEntity(slime, ecs)
    end
    
    -- Centralizar câmera no slime
    local slimeTransform = ecs:getComponent(slime, "Transform")
    if slimeTransform then
        camera.x = slimeTransform.x
        camera.y = slimeTransform.y
        Logger:info("🎯 Câmera centralizada no slime", {x = camera.x, y = camera.y})
    end
    
    -- Gerar sprite para o slime
    local slimeSettings = {
        spriteType = "character",
        size = 16,
        paletteType = "NES", 
        complexity = 40,
        symmetry = "vertical",
        colorCount = 6,
        structureSeed = 12345,
        visualSeed = 54321,
        class = "mage",
        outline = true,
        silhouetteStyle = "chibi"
    }
    
    local sprite = ecs:getComponent(slime, "Sprite")
    sprite.texture = generateSpriteForEntity(slime, slimeSettings)
    sprite.color = {0.3, 0.8, 0.4, 1} -- Verde slime
    
    -- Spawnar entidades baseado no mundo gerado
    spawnEntitiesFromWorld()
    
    print("SLIME: Tempest Trials - Jogo iniciado!")
    print("Controles: WASD - mover, Space - predar, A - analisar")
end

function love.update(dt)
    -- Atualizar aplicação principal
    if app then
        app:update(dt)
    end
    
    -- Atualizar sistemas
    if world then world:update(dt) end
    if skills then 
        -- Verificar evoluções disponíveis
        local slimes = ecs:getEntitiesWith("SlimeCore")
        if #slimes > 0 then
            local evolutions = skills:checkEvolutions(slimes[1], ecs)
            if #evolutions > 0 then
                ui:addNotification("Evolução disponível!", UIColors.warning, 3.0)
            end
        end
    end
    if ui then ui:update(dt) end
    
    -- Atualizar ECS
    ecs:update(dt)
    
    -- Input do jogador
    handlePlayerInput(dt)
    
    -- Atualizar câmera
    updateCamera(dt)
end

function love.draw()
    -- Limpar tela com cor de fundo
    love.graphics.setColor(0.2, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    
    if world then
        love.graphics.push()
        love.graphics.translate(-camera.x * camera.scale + love.graphics.getWidth() / 2, 
                               -camera.y * camera.scale + love.graphics.getHeight() / 2)
        love.graphics.scale(camera.scale)
        
        drawWorldTiles()
        
        love.graphics.pop()
    end
    ecs:update(0) -- Apenas renderização
 
    -- Renderizar entidades manualmente (para debug)
    local entities = ecs:getEntitiesWith("Transform", "Sprite")
    Logger:debug("Renderizando entidades manualmente", {count = #entities})
    
    for _, entity in ipairs(entities) do
        local transform = ecs:getComponent(entity, "Transform")
        local sprite = ecs:getComponent(entity, "Sprite")
        
        if transform and sprite then
            -- Aplicar transformação da câmera
            local screenX = (transform.x - camera.x) * camera.scale + love.graphics.getWidth() / 2
            local screenY = (transform.y - camera.y) * camera.scale + love.graphics.getHeight() / 2
            
            -- Renderizar sprite
            love.graphics.setColor(sprite.color or {1, 1, 1, 1})
            
            -- Desenhar retângulo simples com borda
            local size = sprite.size * camera.scale * transform.scale
            local x = screenX - size / 2
            local y = screenY - size / 2
            
            -- Desenhar preenchimento
            love.graphics.rectangle("fill", x, y, size, size)
            
            -- Desenhar borda
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", x, y, size, size)
            
            -- Indicador especial para slime
            if ecs:hasComponent(entity, "SlimeCore") then
                love.graphics.setColor(1, 1, 0, 1) -- Amarelo
                love.graphics.circle("line", screenX, screenY, 30)
                love.graphics.print("SLIME", screenX - 25, screenY - 40)
                Logger:debug("Slime renderizado", {x = screenX, y = screenY, size = size})
            end
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    
    if combat then
        love.graphics.push()
        love.graphics.translate(-camera.x * camera.scale + love.graphics.getWidth() / 2, 
                               -camera.y * camera.scale + love.graphics.getHeight() / 2)
        love.graphics.scale(camera.scale)
        
        combat:draw()
        
        love.graphics.pop()
    end
    
    -- USAR UI do sistema (não debug info manual)
    if ui then
        ui:draw("playing")
    end
    
    -- Debug info detalhado
    if love.keyboard.isDown("f1") then
        love.graphics.setColor(1, 1, 1, 0.8)
        local y = 10
        love.graphics.print("FPS: " .. love.timer.getFPS(), 10, y); y = y + 20
        love.graphics.print("Entidades: " .. (ecs:getStats().entities or 0), 10, y); y = y + 20
        love.graphics.print("Câmera: " .. math.floor(camera.x) .. ", " .. math.floor(camera.y), 10, y); y = y + 20
        
        if world then
            love.graphics.print("Bioma: " .. (world.currentBiome or "unknown"), 10, y); y = y + 20
            love.graphics.print("Nível: " .. (world.currentLevel or 0), 10, y); y = y + 20
        end
        
        -- Mostrar slimes
        local slimes = ecs:getEntitiesWith("SlimeCore", "Transform")
        love.graphics.print("Slimes: " .. #slimes, 10, y); y = y + 20
        
        for i, slime in ipairs(slimes) do
            local transform = ecs:getComponent(slime, "Transform")
            if transform then
                love.graphics.print("Slime " .. i .. ": " .. math.floor(transform.x) .. ", " .. math.floor(transform.y), 10, y)
                y = y + 15
            end
        end
        
        -- Mostrar controles de debug
        y = y + 20
        love.graphics.print("F1: Debug Info", 10, y); y = y + 15
        love.graphics.print("F2: Log Render", 10, y); y = y + 15
        love.graphics.print("F3: Entity IDs", 10, y); y = y + 15
        love.graphics.print("F4: Save Logs", 10, y); y = y + 15
        love.graphics.print("F5: Show Logs", 10, y); y = y + 15
    end
    
    -- Mostrar logs na tela
    if love.keyboard.isDown("f5") then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setColor(1, 1, 1, 1)
        
        local logs = Logger:getHistory()
        local y = 10
        love.graphics.print("=== LOGS ===", 10, y); y = y + 25
        
        for i = #logs, math.max(1, #logs - 20), -1 do
            local entry = logs[i]
            local levelStr = ""
            if entry.level == 1 then levelStr = "DEBUG"
            elseif entry.level == 2 then levelStr = "INFO"
            elseif entry.level == 3 then levelStr = "WARN"
            elseif entry.level == 4 then levelStr = "ERROR"
            end
            
            love.graphics.print("[" .. entry.timestamp .. "] " .. levelStr .. ": " .. entry.message, 10, y)
            y = y + 15
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

local function addWorldCollisionSystem()
    ecs:addSystem("world_collision", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Velocity", "Collider")
        
        for _, entity in ipairs(entities) do
            local transform = ecsInstance:getComponent(entity, "Transform")
            local velocity = ecsInstance:getComponent(entity, "Velocity")
            local collider = ecsInstance:getComponent(entity, "Collider")
            
            -- Calcular nova posição
            local newX = transform.x + velocity.vx * dt
            local newY = transform.y + velocity.vy * dt
            
            -- Verificar colisão com tiles do mundo
            local tileSize = 32
            local gridX = math.floor(newX / tileSize)
            local gridY = math.floor(newY / tileSize)
            
            if world and world:getTileAt(gridX, gridY) == 2 then -- WALL
                -- Colidir com parede - parar movimento
                velocity.vx = velocity.vx * -0.5
                velocity.vy = velocity.vy * -0.5
            else
                -- Movimento livre
                transform.x = newX
                transform.y = newY
            end
        end
    end, 15) -- Antes do movimento normal
end


function love.keypressed(key)
    Logger:debug("Tecla pressionada", {key = key})
    if ui and ui:keypressed(key) then
        return -- UI capturou input
    end    
    if key == "escape" then
        Logger:info("🚪 Saindo do jogo...")
        love.event.quit()
    elseif key == "space" then
        -- Predação via sistema integrado
        local slimes = ecs:getEntitiesWith("SlimeCore", "Transform")
        if #slimes > 0 and app and app.slime then
            local transform = ecs:getComponent(slimes[1], "Transform")
            local success, msg = app.slime:tryPredation(transform.x, transform.y)
            if ui then 
                ui:addNotification(msg, success and UIColors.success or UIColors.error, 2.0) 
            end
        end
    
    elseif key == "a" then
        -- Análise via sistema integrado
        local slimes = ecs:getEntitiesWith("SlimeCore")
        if #slimes > 0 and app and app.slime then
            local success, msg = app.slime:startAnalysis()
            if ui then 
                ui:addNotification(msg, success and UIColors.success or UIColors.error, 2.0) 
            end
        end
    
    elseif key == "f4" then
        -- Salvar logs
        Logger:info("💾 Salvando logs...")
        Logger:saveToFile("game_log.txt")
        Logger:info("✅ Logs salvos em game_log.txt")
    elseif key == "space" then
        -- Tentar predação
        local slimes = ecs:getEntitiesWith("SlimeCore", "Transform")
        if #slimes > 0 then
            local slime = slimes[1]
            local transform = ecs:getComponent(slime, "Transform")
            
            if app and app.slime and app.slime.predation then
                local success, msg = app.slime.predation:tryPredateAt(slime, transform.x, transform.y, ecs)
                if ui then ui:addNotification(msg, success and UIColors.success or UIColors.error, 2.0) end
            end
        end
    elseif key == "a" then
        -- Iniciar análise
        local slimes = ecs:getEntitiesWith("SlimeCore")
        if #slimes > 0 and app and app.slime and app.slime.analysis then
            local success, msg = app.slime.analysis:startAnalysis(slimes[1], ecs)
            if ui then ui:addNotification(msg, success and UIColors.success or UIColors.error, 2.0) end
        end
    elseif key == "q" then
        -- Ativar próxima forma disponível
        if app and app.slime then
            local forms = app.slime:getAvailableForms()
            for _, formData in ipairs(forms) do
                if formData.available then
                    local success, msg = app.slime:mimicForm(formData.form.id)
                    if ui then ui:addNotification(msg, success and UIColors.warning or UIColors.error, 3.0) end
                    break
                end
            end
        end
    elseif key == "e" then
        -- Reverter forma
        if app and app.slime then
            app.slime:revertForm()
        end
    elseif key == "t" then
        -- Testar habilidade única
        if skills and app and app.slime then
            local slimes = ecs:getEntitiesWith("SlimeCore")
            if #slimes > 0 then
                local success, msg = skills:useUniqueSkill(slimes[1], "gluttony", ecs)
                if ui then ui:addNotification(msg, success and UIColors.mana or UIColors.error, 3.0) end
            end
        end
    elseif key == "n" then
        -- Próximo nível (debug)
        if world then
            world:nextLevel()
            spawnEntitiesFromWorld()
            if ui then ui:addNotification("Novo nível gerado!", UIColors.accent, 3.0) end
        end
    elseif key == "r" then
        -- Respawnar inimigos (debug)
        spawnRandomEnemies()
    end
    
    -- Propagar para UI
    if ui then
        ui:keypressed(key)
    end
    
    -- Propagar para app
    if app and app.keypressed then
        app:keypressed(key)
    end
end

local function checkWorldCollision(x, y, radius, world)
    if not world then return false end
    
    local tileSize = 32
    local margin = radius + 2
    
    -- Verificar tiles ao redor da posição
    local minTileX = math.floor((x - margin) / tileSize)
    local maxTileX = math.floor((x + margin) / tileSize)
    local minTileY = math.floor((y - margin) / tileSize)
    local maxTileY = math.floor((y + margin) / tileSize)
    
    for tileY = minTileY, maxTileY do
        for tileX = minTileX, maxTileX do
            local tile = world:getTileAt(tileX, tileY)
            
            if tile == 2 then -- WALL
                -- Verificar colisão círculo-retângulo
                local tileWorldX = tileX * tileSize
                local tileWorldY = tileY * tileSize
                
                if circleRectCollision(x, y, radius, 
                                     tileWorldX, tileWorldY, tileSize, tileSize) then
                    return true
                end
            end
        end
    end
    
    return false
end

local function circleRectCollision(circleX, circleY, radius, rectX, rectY, rectW, rectH)
    -- Encontrar ponto mais próximo do retângulo ao círculo
    local closestX = math.max(rectX, math.min(circleX, rectX + rectW))
    local closestY = math.max(rectY, math.min(circleY, rectY + rectH))
    
    -- Calcular distância
    local dx = circleX - closestX
    local dy = circleY - closestY
    
    return (dx * dx + dy * dy) < (radius * radius)
end


function love.mousepressed(x, y, button)
    -- Primeiro verificar se UI capturou o clique
    if ui and ui:mousepressed(x, y, button) then
        return -- UI capturou o evento
    end
    
    if button == 1 then
        -- Tentar predação na posição do mouse
        local worldX = (x - love.graphics.getWidth() / 2) / camera.scale + camera.x
        local worldY = (y - love.graphics.getHeight() / 2) / camera.scale + camera.y
        
        local slimes = ecs:getEntitiesWith("SlimeCore")
        if #slimes > 0 and app and app.slime and app.slime.predation then
            local success, msg = app.slime.predation:tryPredateAt(slimes[1], worldX, worldY, ecs)
            if ui then ui:addNotification(msg, success and UIColors.success or UIColors.error, 2.0) end
        end
    elseif button == 2 then
        -- Clique direito para ataque corpo a corpo
        if combat then
            local slimes = ecs:getEntitiesWith("SlimeCore")
            if #slimes > 0 then
                local success, msg = combat:playerAttack(slimes[1], ecs)
                if ui then ui:addNotification(msg, success and UIColors.warning or UIColors.error, 2.0) end
            end
        end
    end
    
    -- Propagar para app
    if app and app.mousepressed then
        app:mousepressed(x, y, button)
    end
end 