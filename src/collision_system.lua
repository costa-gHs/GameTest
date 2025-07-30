-- collision_system.lua - Sistema de Colisão Avançado
-- Integra colisão com mundo, entidades e combate

local CollisionSystem = {}

function CollisionSystem:new()
    local cs = {}
    setmetatable(cs, { __index = self })
    
    cs.spatialGrid = {} -- Grid espacial para otimização
    cs.gridSize = 64
    cs.collisionPairs = {}
    
    return cs
end

function CollisionSystem:addToECS(ecs, world)
    -- Sistema de colisão com mundo
    ecs:addSystem("world_collision", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Velocity", "Collider")
        
        for _, entity in ipairs(entities) do
            local transform = ecsInstance:getComponent(entity, "Transform")
            local velocity = ecsInstance:getComponent(entity, "Velocity")
            local collider = ecsInstance:getComponent(entity, "Collider")
            
            -- Calcular nova posição
            local newX = transform.x + velocity.vx * dt
            local newY = transform.y + velocity.vy * dt
            
            -- Verificar colisão X
            if not self:checkWorldCollision(newX, transform.y, collider.radius, world) then
                transform.x = newX
            else
                velocity.vx = 0
                -- Efeito de "slide" ao longo da parede
                if not self:checkWorldCollision(transform.x, newY, collider.radius, world) then
                    transform.y = newY
                    velocity.vy = velocity.vy * 0.8 -- Preservar movimento perpendicular
                end
            end
            
            -- Verificar colisão Y
            if not self:checkWorldCollision(transform.x, newY, collider.radius, world) then
                transform.y = newY
            else
                velocity.vy = 0
                -- Efeito de "slide" ao longo da parede
                if not self:checkWorldCollision(newX, transform.y, collider.radius, world) then
                    transform.x = newX
                    velocity.vx = velocity.vx * 0.8
                end
            end
        end
    end, 12)
    
    -- Sistema de colisão entre entidades
    ecs:addSystem("entity_collision", function(dt, ecsInstance)
        local entities = ecsInstance:getEntitiesWith("Transform", "Collider")
        
        -- Usar grid espacial para otimização
        self:updateSpatialGrid(entities, ecsInstance)
        
        for i = 1, #entities do
            local entityA = entities[i]
            local transformA = ecsInstance:getComponent(entityA, "Transform")
            local colliderA = ecsInstance:getComponent(entityA, "Collider")
            
            -- Buscar apenas entidades próximas
            local nearbyEntities = self:getNearbyEntities(transformA.x, transformA.y, entities, ecsInstance)
            
            for _, entityB in ipairs(nearbyEntities) do
                if entityA.id < entityB.id then -- Evitar duplicatas
                    local transformB = ecsInstance:getComponent(entityB, "Transform")
                    local colliderB = ecsInstance:getComponent(entityB, "Collider")
                    
                    if self:checkCircleCollision(transformA, colliderA, transformB, colliderB) then
                        self:resolveCollision(entityA, entityB, ecsInstance)
                    end
                end
            end
        end
    end, 13)
    
    -- Sistema de colisão de combate
    ecs:addSystem("combat_collision", function(dt, ecsInstance)
        local combatEntities = ecsInstance:getEntitiesWith("Combat", "Transform", "Collider")
        
        for _, attacker in ipairs(combatEntities) do
            local attackerCombat = ecsInstance:getComponent(attacker, "Combat")
            local attackerTransform = ecsInstance:getComponent(attacker, "Transform")
            local attackerCollider = ecsInstance:getComponent(attacker, "Collider")
            
            if attackerCombat.state == "attacking" then
                -- Criar hitbox temporária do ataque
                local hitbox = {
                    x = attackerTransform.x + (attackerCombat.attackDirection and attackerCombat.attackDirection.x * 30 or 0),
                    y = attackerTransform.y + (attackerCombat.attackDirection and attackerCombat.attackDirection.y * 30 or 0),
                    radius = attackerCollider.radius + 20
                }
                
                for _, target in ipairs(combatEntities) do
                    if target ~= attacker then
                        local targetTransform = ecsInstance:getComponent(target, "Transform")
                        local targetCollider = ecsInstance:getComponent(target, "Collider")
                        local targetCombat = ecsInstance:getComponent(target, "Combat")
                        
                        -- Verificar se está na hitbox
                        local dx = targetTransform.x - hitbox.x
                        local dy = targetTransform.y - hitbox.y
                        local distance = math.sqrt(dx * dx + dy * dy)
                        
                        if distance < hitbox.radius + targetCollider.radius then
                            -- Aplicar dano se não tem i-frames
                            if not targetCombat.iFramesTimer or targetCombat.iFramesTimer <= 0 then
                                self:applyAttackDamage(attacker, target, ecsInstance)
                            end
                        end
                    end
                end
            end
        end
    end, 35)
end

function CollisionSystem:checkWorldCollision(x, y, radius, world)
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
                
                if self:circleRectCollision(x, y, radius, 
                                           tileWorldX, tileWorldY, tileSize, tileSize) then
                    return true
                end
            end
        end
    end
    
    return false
end

function CollisionSystem:circleRectCollision(circleX, circleY, radius, rectX, rectY, rectW, rectH)
    -- Encontrar ponto mais próximo do retângulo ao círculo
    local closestX = math.max(rectX, math.min(circleX, rectX + rectW))
    local closestY = math.max(rectY, math.min(circleY, rectY + rectH))
    
    -- Calcular distância
    local dx = circleX - closestX
    local dy = circleY - closestY
    
    return (dx * dx + dy * dy) < (radius * radius)
end

function CollisionSystem:checkCircleCollision(transformA, colliderA, transformB, colliderB)
    local dx = transformB.x - transformA.x
    local dy = transformB.y - transformA.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local minDistance = colliderA.radius + colliderB.radius
    
    return distance < minDistance
end

function CollisionSystem:resolveCollision(entityA, entityB, ecs)
    local transformA = ecs:getComponent(entityA, "Transform")
    local transformB = ecs:getComponent(entityB, "Transform")
    local colliderA = ecs:getComponent(entityA, "Collider")
    local colliderB = ecs:getComponent(entityB, "Collider")
    
    -- Verificar se é trigger
    if colliderA.trigger or colliderB.trigger then
        -- Emitir evento de trigger
        local EventBus = require("src.core.eventbus")
        EventBus:emit("collision:trigger", {
            entityA = entityA,
            entityB = entityB
        })
        return
    end
    
    -- Separação física
    local dx = transformB.x - transformA.x
    local dy = transformB.y - transformA.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > 0 then
        local overlap = (colliderA.radius + colliderB.radius) - distance
        local separationX = (dx / distance) * overlap * 0.5
        local separationY = (dy / distance) * overlap * 0.5
        
        transformA.x = transformA.x - separationX
        transformA.y = transformA.y - separationY
        transformB.x = transformB.x + separationX
        transformB.y = transformB.y + separationY
        
        -- Aplicar impulso se têm velocidade
        local velocityA = ecs:getComponent(entityA, "Velocity")
        local velocityB = ecs:getComponent(entityB, "Velocity")
        
        if velocityA and velocityB then
            local impulse = 50
            velocityA.vx = velocityA.vx - separationX * impulse
            velocityA.vy = velocityA.vy - separationY * impulse
            velocityB.vx = velocityB.vx + separationX * impulse
            velocityB.vy = velocityB.vy + separationY * impulse
        end
    end
end

function CollisionSystem:updateSpatialGrid(entities, ecs)
    self.spatialGrid = {}
    
    for _, entity in ipairs(entities) do
        local transform = ecs:getComponent(entity, "Transform")
        local gridX = math.floor(transform.x / self.gridSize)
        local gridY = math.floor(transform.y / self.gridSize)
        local key = gridX .. "," .. gridY
        
        if not self.spatialGrid[key] then
            self.spatialGrid[key] = {}
        end
        table.insert(self.spatialGrid[key], entity)
    end
end

function CollisionSystem:getNearbyEntities(x, y, entities, ecs)
    local nearby = {}
    local gridX = math.floor(x / self.gridSize)
    local gridY = math.floor(y / self.gridSize)
    
    -- Verificar grid atual e adjacentes
    for dx = -1, 1 do
        for dy = -1, 1 do
            local key = (gridX + dx) .. "," .. (gridY + dy)
            if self.spatialGrid[key] then
                for _, entity in ipairs(self.spatialGrid[key]) do
                    table.insert(nearby, entity)
                end
            end
        end
    end
    
    return nearby
end

function CollisionSystem:applyAttackDamage(attacker, target, ecs)
    local attackerCombat = ecs:getComponent(attacker, "Combat")
    local targetHealth = ecs:getComponent(target, "Health")
    local targetSlime = ecs:getComponent(target, "SlimeCore")
    local targetCombat = ecs:getComponent(target, "Combat")
    
    local damage = attackerCombat.attackDamage or 20
    
    -- Aplicar dano
    if targetHealth then
        targetHealth.current = targetHealth.current - damage
    elseif targetSlime then
        targetSlime.health = targetSlime.health - damage
    end
    
    -- Ativar i-frames
    if targetCombat then
        targetCombat.iFramesTimer = 0.5
    end
    
    -- Knockback
    local attackerTransform = ecs:getComponent(attacker, "Transform")
    local targetTransform = ecs:getComponent(target, "Transform")
    local targetVelocity = ecs:getComponent(target, "Velocity")
    
    if targetVelocity then
        local dx = targetTransform.x - attackerTransform.x
        local dy = targetTransform.y - attackerTransform.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 0 then
            local knockback = 150
            targetVelocity.vx = targetVelocity.vx + (dx / distance) * knockback
            targetVelocity.vy = targetVelocity.vy + (dy / distance) * knockback
        end
    end
    
    -- Emitir evento de dano
    local EventBus = require("src.core.eventbus")
    EventBus:emit("combat:damage_applied", {
        attacker = attacker,
        target = target,
        damage = damage
    })
end

return CollisionSystem