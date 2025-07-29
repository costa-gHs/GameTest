-- combat.lua - Sistema de Combate Avançado
-- Inclui i-frames, dash viscoso, agarre/absorção, mecânicas de timing

local CombatSystem = {}
local EventBus = require("src.core.eventbus")
local RNG = require("src.core.rng")

-- Estados de combate
local CombatState = {
    IDLE = "idle",
    ATTACKING = "attacking", 
    DASHING = "dashing",
    GRABBING = "grabbing",
    STUNNED = "stunned",
    INVULNERABLE = "invulnerable"
}

-- Tipos de ataque
local AttackType = {
    MELEE = "melee",
    RANGED = "ranged",
    GRAB = "grab",
    SPECIAL = "special"
}

function CombatSystem:new()
    local cs = {}
    setmetatable(cs, { __index = self })
    
    cs.combatants = {} -- Cache de entidades em combate
    cs.projectiles = {}
    cs.effects = {}
    
    -- Configurações de combate
    cs.config = {
        dashDistance = 80,
        dashDuration = 0.3,
        dashCooldown = 1.5,
        iFramesDuration = 0.5,
        grabRange = 24,
        grabDuration = 1.0,
        attackBuffer = 0.2, -- Janela para input buffering
        perfectDodgeWindow = 0.1 -- Janela para dodge perfeito
    }
    
    return cs
end

function CombatSystem:update(dt, ecs)
    -- Atualizar estados de combate
    self:updateCombatStates(dt, ecs)
    
    -- Atualizar projéteis
    self:updateProjectiles(dt, ecs)
    
    -- Atualizar efeitos visuais
    self:updateEffects(dt)
    
    -- Processar colisões de combate
    self:processCombatCollisions(ecs)
    
    -- Atualizar AI de combate
    self:updateCombatAI(dt, ecs)
end

function CombatSystem:updateCombatStates(dt, ecs)
    local combatEntities = ecs:getEntitiesWith("Combat", "Transform")
    
    for _, entity in ipairs(combatEntities) do
        local combat = ecs:getComponent(entity, "Combat")
        local transform = ecs:getComponent(entity, "Transform")
        local velocity = ecs:getComponent(entity, "Velocity")
        
        -- Atualizar timers
        if combat.stateTimer then
            combat.stateTimer = combat.stateTimer - dt
            if combat.stateTimer <= 0 then
                self:transitionCombatState(entity, CombatState.IDLE, ecs)
            end
        end
        
        if combat.dashCooldownTimer then
            combat.dashCooldownTimer = math.max(0, combat.dashCooldownTimer - dt)
        end
        
        if combat.attackCooldownTimer then
            combat.attackCooldownTimer = math.max(0, combat.attackCooldownTimer - dt)
        end
        
        if combat.iFramesTimer then
            combat.iFramesTimer = math.max(0, combat.iFramesTimer - dt)
        end
        
        -- Processar estado atual
        if combat.state == CombatState.DASHING then
            self:updateDash(entity, dt, ecs)
        elseif combat.state == CombatState.ATTACKING then
            self:updateAttack(entity, dt, ecs)
        elseif combat.state == CombatState.GRABBING then
            self:updateGrab(entity, dt, ecs)
        end
    end
end

function CombatSystem:transitionCombatState(entity, newState, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    if not combat then return end
    
    local oldState = combat.state
    combat.state = newState
    combat.stateTimer = nil
    
    -- Callbacks de transição
    if newState == CombatState.IDLE then
        combat.targetEntity = nil
        combat.grabTarget = nil
    elseif newState == CombatState.INVULNERABLE then
        combat.stateTimer = self.config.iFramesDuration
        combat.iFramesTimer = self.config.iFramesDuration
    end
    
    EventBus:emit("combat:state_changed", {
        entity = entity,
        oldState = oldState,
        newState = newState
    })
end

-- Sistema de Dash Viscoso
function CombatSystem:startDash(entity, direction, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local velocity = ecs:getComponent(entity, "Velocity")
    
    if not combat or not velocity then return false end
    
    -- Verificar cooldown
    if combat.dashCooldownTimer and combat.dashCooldownTimer > 0 then
        return false, "Dash em cooldown"
    end
    
    -- Verificar se pode fazer dash
    if combat.state == CombatState.ATTACKING or combat.state == CombatState.GRABBING then
        return false, "Não pode fazer dash agora"
    end
    
    -- Iniciar dash
    self:transitionCombatState(entity, CombatState.DASHING, ecs)
    combat.stateTimer = self.config.dashDuration
    combat.dashCooldownTimer = self.config.dashCooldown
    
    -- Aplicar impulso
    local dashSpeed = self.config.dashDistance / self.config.dashDuration
    velocity.vx = direction.x * dashSpeed
    velocity.vy = direction.y * dashSpeed
    
    -- Dash dá i-frames curtos
    combat.iFramesTimer = self.config.dashDuration * 0.7
    
    -- Efeito visual
    self:createDashEffect(entity, ecs)
    
    EventBus:emit("combat:dash_started", {
        entity = entity,
        direction = direction
    })
    
    return true, "Dash executado"
end

function CombatSystem:updateDash(entity, dt, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local velocity = ecs:getComponent(entity, "Velocity")
    
    if not combat or not velocity then return end
    
    -- Aplicar atrito do dash (viscoso)
    local friction = 0.85
    velocity.vx = velocity.vx * friction
    velocity.vy = velocity.vy * friction
    
    -- Verificar colisão durante dash para absorção
    local collisions = self:getDashCollisions(entity, ecs)
    for _, target in ipairs(collisions) do
        if ecs:hasComponent(entity, "SlimeCore") then
            -- Slime pode absorver durante dash
            self:attemptGrabDuringDash(entity, target, ecs)
        end
    end
end

function CombatSystem:attemptGrabDuringDash(entity, target, ecs)
    -- Tentativa de agarre durante dash
    if not target or not target.active then return end
    
    local entityTransform = ecs:getComponent(entity, "Transform")
    local targetTransform = ecs:getComponent(target, "Transform")
    
    if not entityTransform or not targetTransform then return end
    
    local dx = targetTransform.x - entityTransform.x
    local dy = targetTransform.y - entityTransform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Se está próximo o suficiente, tentar predação
    if distance < 20 then
        if ecs:hasComponent(entity, "SlimeCore") then
            -- Tentar predação automática
            EventBus:emit("predation:attempt", {
                predator = entity,
                target = target,
                automatic = true
            })
        end
    end
end

-- Sistema de Agarre/Absorção
function CombatSystem:startGrab(entity, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local transform = ecs:getComponent(entity, "Transform")
    
    if not combat or not transform then return false end
    
    if combat.state ~= CombatState.IDLE then
        return false, "Não pode agarrar agora"
    end
    
    -- Encontrar alvo próximo
    local target = self:findGrabTarget(entity, ecs)
    if not target then
        return false, "Nenhum alvo ao alcance"
    end
    
    -- Iniciar agarre
    self:transitionCombatState(entity, CombatState.GRABBING, ecs)
    combat.stateTimer = self.config.grabDuration
    combat.grabTarget = target
    combat.attackCooldownTimer = self.config.grabDuration + 0.5
    
    -- Puxar alvo para perto
    self:pullTargetTowards(target, entity, ecs)
    
    EventBus:emit("combat:grab_started", {
        entity = entity,
        target = target
    })
    
    return true, "Agarre iniciado"
end

function CombatSystem:updateGrab(entity, dt, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    
    if not combat or not combat.grabTarget then return end
    
    local target = combat.grabTarget
    
    -- Verificar se alvo ainda existe
    if not target.active then
        self:transitionCombatState(entity, CombatState.IDLE, ecs)
        return
    end
    
    -- Continuar puxando alvo
    self:pullTargetTowards(target, entity, ecs)
    
    -- No final do agarre, tentar predação
    if combat.stateTimer and combat.stateTimer <= 0.1 then
        if ecs:hasComponent(entity, "SlimeCore") then
            self:attemptGrabPredation(entity, target, ecs)
        end
    end
end

function CombatSystem:pullTargetTowards(target, grabber, ecs)
    local targetTransform = ecs:getComponent(target, "Transform")
    local grabberTransform = ecs:getComponent(grabber, "Transform")
    local targetVelocity = ecs:getComponent(target, "Velocity")
    
    if not targetTransform or not grabberTransform or not targetVelocity then return end
    
    local dx = grabberTransform.x - targetTransform.x
    local dy = grabberTransform.y - targetTransform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > 5 then
        local pullForce = 200
        targetVelocity.vx = targetVelocity.vx + (dx / distance) * pullForce * love.timer.getDelta()
        targetVelocity.vy = targetVelocity.vy + (dy / distance) * pullForce * love.timer.getDelta()
    end
end

-- Sistema de Ataques
function CombatSystem:performAttack(entity, attackType, direction, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    
    if not combat then return false end
    
    -- Verificar cooldown
    if combat.attackCooldownTimer and combat.attackCooldownTimer > 0 then
        return false, "Ataque em cooldown"
    end
    
    if combat.state ~= CombatState.IDLE then
        return false, "Não pode atacar agora"
    end
    
    -- Executar ataque baseado no tipo
    if attackType == AttackType.MELEE then
        return self:performMeleeAttack(entity, direction, ecs)
    elseif attackType == AttackType.GRAB then
        return self:startGrab(entity, ecs)
    elseif attackType == AttackType.RANGED then
        return self:performRangedAttack(entity, direction, ecs)
    end
    
    return false, "Tipo de ataque inválido"
end

function CombatSystem:performMeleeAttack(entity, direction, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local transform = ecs:getComponent(entity, "Transform")
    
    self:transitionCombatState(entity, CombatState.ATTACKING, ecs)
    combat.stateTimer = 0.4
    combat.attackCooldownTimer = 0.8
    
    -- Criar hitbox do ataque
    local hitbox = self:createMeleeHitbox(entity, direction, ecs)
    
    -- Verificar alvos atingidos
    local targets = self:getTargetsInHitbox(entity, hitbox, ecs)
    for _, target in ipairs(targets) do
        self:applyDamage(target, entity, 25, ecs)
    end
    
    EventBus:emit("combat:melee_attack", {
        entity = entity,
        direction = direction,
        targets = targets
    })
    
    return true, "Ataque corpo a corpo executado"
end

function CombatSystem:performRangedAttack(entity, direction, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local transform = ecs:getComponent(entity, "Transform")
    
    self:transitionCombatState(entity, CombatState.ATTACKING, ecs)
    combat.stateTimer = 0.3
    combat.attackCooldownTimer = 1.2
    
    -- Criar projétil
    local projectile = self:createProjectile(entity, direction, ecs)
    table.insert(self.projectiles, projectile)
    
    EventBus:emit("combat:ranged_attack", {
        entity = entity,
        direction = direction,
        projectile = projectile
    })
    
    return true, "Ataque à distância executado"
end

-- Sistema de Dano e I-Frames
function CombatSystem:applyDamage(target, source, damage, ecs)
    local combat = ecs:getComponent(target, "Combat")
    local health = ecs:getComponent(target, "Health")
    local slimeCore = ecs:getComponent(target, "SlimeCore")
    
    -- Verificar i-frames
    if combat and combat.iFramesTimer and combat.iFramesTimer > 0 then
        EventBus:emit("combat:damage_blocked", {
            target = target,
            source = source,
            reason = "i-frames"
        })
        return false
    end
    
    -- Aplicar dano
    local actualDamage = damage
    
    -- Calcular modificadores de dano
    if combat and combat.defenseModifier then
        actualDamage = actualDamage * (1 - combat.defenseModifier)
    end
    
    -- Aplicar dano à vida
    if health then
        health.current = health.current - actualDamage
    elseif slimeCore then
        slimeCore.health = slimeCore.health - actualDamage
    else
        return false
    end
    
    -- Ativar i-frames
    if combat then
        combat.iFramesTimer = self.config.iFramesDuration
        self:transitionCombatState(target, CombatState.INVULNERABLE, ecs)
    end
    
    -- Efeito de knockback
    self:applyKnockback(target, source, actualDamage, ecs)
    
    -- Verificar se morreu
    local currentHealth = health and health.current or (slimeCore and slimeCore.health or 0)
    if currentHealth <= 0 then
        self:handleEntityDeath(target, source, ecs)
    end
    
    EventBus:emit("combat:damage_applied", {
        target = target,
        source = source,
        damage = actualDamage,
        fatal = currentHealth <= 0
    })
    
    return true
end

function CombatSystem:applyKnockback(target, source, damage, ecs)
    local targetTransform = ecs:getComponent(target, "Transform")
    local sourceTransform = ecs:getComponent(source, "Transform")
    local targetVelocity = ecs:getComponent(target, "Velocity")
    
    if not targetTransform or not sourceTransform or not targetVelocity then return end
    
    local dx = targetTransform.x - sourceTransform.x
    local dy = targetTransform.y - sourceTransform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > 0 then
        local knockbackForce = damage * 2
        targetVelocity.vx = targetVelocity.vx + (dx / distance) * knockbackForce
        targetVelocity.vy = targetVelocity.vy + (dy / distance) * knockbackForce
    end
end

-- Funções auxiliares
function CombatSystem:findGrabTarget(entity, ecs)
    local transform = ecs:getComponent(entity, "Transform")
    if not transform then return nil end
    
    local entities = ecs:getEntitiesWith("Transform", "Collider")
    local closestTarget = nil
    local closestDistance = self.config.grabRange
    
    for _, target in ipairs(entities) do
        if target ~= entity then
            local targetTransform = ecs:getComponent(target, "Transform")
            local dx = targetTransform.x - transform.x
            local dy = targetTransform.y - transform.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance < closestDistance then
                -- Verificar se pode ser agarrado
                if self:canBeGrabbed(target, ecs) then
                    closestTarget = target
                    closestDistance = distance
                end
            end
        end
    end
    
    return closestTarget
end

function CombatSystem:canBeGrabbed(entity, ecs)
    -- Não pode agarrar outros slimes
    if ecs:hasComponent(entity, "SlimeCore") then
        return false
    end
    
    local combat = ecs:getComponent(entity, "Combat")
    if combat and combat.state == CombatState.GRABBING then
        return false -- Já sendo agarrado
    end
    
    return true
end

function CombatSystem:createMeleeHitbox(entity, direction, ecs)
    local transform = ecs:getComponent(entity, "Transform")
    if not transform then return nil end
    
    local range = 32
    return {
        x = transform.x + direction.x * range,
        y = transform.y + direction.y * range,
        radius = 20,
        lifetime = 0.1
    }
end

function CombatSystem:getTargetsInHitbox(source, hitbox, ecs)
    if not hitbox then return {} end
    
    local targets = {}
    local entities = ecs:getEntitiesWith("Transform", "Collider")
    
    for _, entity in ipairs(entities) do
        if entity ~= source then
            local transform = ecs:getComponent(entity, "Transform")
            local collider = ecs:getComponent(entity, "Collider")
            
            local dx = transform.x - hitbox.x
            local dy = transform.y - hitbox.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance < hitbox.radius + collider.radius then
                table.insert(targets, entity)
            end
        end
    end
    
    return targets
end

function CombatSystem:getDashCollisions(entity, ecs)
    local transform = ecs:getComponent(entity, "Transform")
    local collider = ecs:getComponent(entity, "Collider")
    
    if not transform or not collider then return {} end
    
    local collisions = {}
    local entities = ecs:getEntitiesWith("Transform", "Collider")
    
    for _, target in ipairs(entities) do
        if target ~= entity then
            local targetTransform = ecs:getComponent(target, "Transform")
            local targetCollider = ecs:getComponent(target, "Collider")
            
            local dx = targetTransform.x - transform.x
            local dy = targetTransform.y - transform.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance < collider.radius + targetCollider.radius then
                table.insert(collisions, target)
            end
        end
    end
    
    return collisions
end

function CombatSystem:handleEntityDeath(entity, killer, ecs)
    EventBus:emit("combat:entity_died", {
        entity = entity,
        killer = killer
    })
    
    -- Converter em lootable se necessário
    if not ecs:hasComponent(entity, "Lootable") then
        ecs:addComponent(entity, "Lootable", {
            essence = RNG:randomInt(3, 8),
            traits = {"basic_combat"},
            dropChance = 0.8
        })
    end
end

function CombatSystem:createDashEffect(entity, ecs)
    local transform = ecs:getComponent(entity, "Transform")
    if not transform then return end
    
    table.insert(self.effects, {
        type = "dash_trail",
        x = transform.x,
        y = transform.y,
        lifetime = 0.3,
        timer = 0
    })
end

function CombatSystem:updateProjectiles(dt, ecs)
    -- Sistema de projéteis (implementação básica)
    -- Por enquanto, apenas placeholder
end

function CombatSystem:processCombatCollisions(ecs)
    -- Processar colisões de combate
    local combatEntities = ecs:getEntitiesWith("Combat", "Transform", "Collider")
    
    for i = 1, #combatEntities do
        for j = i + 1, #combatEntities do
            local entityA = combatEntities[i]
            local entityB = combatEntities[j]
            
            local transformA = ecs:getComponent(entityA, "Transform")
            local transformB = ecs:getComponent(entityB, "Transform")
            local colliderA = ecs:getComponent(entityA, "Collider")
            local colliderB = ecs:getComponent(entityB, "Collider")
            local combatA = ecs:getComponent(entityA, "Combat")
            local combatB = ecs:getComponent(entityB, "Combat")
            
            if transformA and transformB and colliderA and colliderB and combatA and combatB then
                local dx = transformB.x - transformA.x
                local dy = transformB.y - transformA.y
                local distance = math.sqrt(dx * dx + dy * dy)
                local minDistance = colliderA.radius + colliderB.radius
                
                if distance < minDistance then
                    -- Verificar se um está atacando
                    if combatA.state == CombatState.ATTACKING and combatB.state ~= CombatState.INVULNERABLE then
                        self:applyDamage(entityA, entityB, combatA.attackDamage, ecs)
                    elseif combatB.state == CombatState.ATTACKING and combatA.state ~= CombatState.INVULNERABLE then
                        self:applyDamage(entityB, entityA, combatB.attackDamage, ecs)
                    end
                end
            end
        end
    end
end

function CombatSystem:updateCombatAI(dt, ecs)
    -- AI de combate para inimigos
    local enemies = ecs:getEntitiesWith("Combat", "Transform", "AI")
    
    for _, enemy in ipairs(enemies) do
        local ai = ecs:getComponent(enemy, "AI")
        local combat = ecs:getComponent(enemy, "Combat")
        local transform = ecs:getComponent(enemy, "Transform")
        local velocity = ecs:getComponent(enemy, "Velocity")
        
        if ai and combat and transform and velocity then
            -- AI básica: perseguir jogador mais próximo
            local player = self:findNearestPlayer(enemy, ecs)
            if player then
                local playerTransform = ecs:getComponent(player, "Transform")
                local dx = playerTransform.x - transform.x
                local dy = playerTransform.y - transform.y
                local distance = math.sqrt(dx * dx + dy * dy)
                
                if distance > 50 then
                    -- Perseguir
                    local moveSpeed = ai.moveSpeed or 50 -- Valor padrão se não definido
                    velocity.vx = (dx / distance) * moveSpeed
                    velocity.vy = (dy / distance) * moveSpeed
                else
                    -- Atacar
                    if combat.attackCooldownTimer <= 0 then
                        self:performAttack(enemy, AttackType.MELEE, {x = dx, y = dy}, ecs)
                    end
                end
            end
        end
    end
end

function CombatSystem:updateAttack(entity, dt, ecs)
    local combat = ecs:getComponent(entity, "Combat")
    local transform = ecs:getComponent(entity, "Transform")
    
    if not combat or not transform then return end
    
    -- Atualizar animação de ataque
    if combat.attackTimer then
        combat.attackTimer = combat.attackTimer - dt
        
        if combat.attackTimer <= 0 then
            self:transitionCombatState(entity, CombatState.IDLE, ecs)
        end
    end
end

function CombatSystem:findNearestPlayer(enemy, ecs)
    local players = ecs:getEntitiesWith("SlimeCore", "Transform")
    local nearest = nil
    local nearestDistance = math.huge
    
    for _, player in ipairs(players) do
        local enemyTransform = ecs:getComponent(enemy, "Transform")
        local playerTransform = ecs:getComponent(player, "Transform")
        
        local dx = playerTransform.x - enemyTransform.x
        local dy = playerTransform.y - enemyTransform.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance < nearestDistance then
            nearest = player
            nearestDistance = distance
        end
    end
    
    return nearest
end

function CombatSystem:updateEffects(dt)
    for i = #self.effects, 1, -1 do
        local effect = self.effects[i]
        effect.timer = effect.timer + dt
        
        if effect.timer >= effect.lifetime then
            table.remove(self.effects, i)
        end
    end
end

function CombatSystem:draw()
    -- Desenhar efeitos visuais
    for _, effect in ipairs(self.effects) do
        if effect.type == "dash_trail" then
            local alpha = 1 - (effect.timer / effect.lifetime)
            love.graphics.setColor(1, 1, 1, alpha * 0.5)
            love.graphics.circle("fill", effect.x, effect.y, 8)
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end

-- Interface para ações do jogador
function CombatSystem:playerDash(playerEntity, direction, ecs)
    return self:startDash(playerEntity, direction, ecs)
end

function CombatSystem:playerAttack(playerEntity, ecs)
    return self:performAttack(playerEntity, AttackType.MELEE, {x = 1, y = 0}, ecs)
end

function CombatSystem:playerGrab(playerEntity, ecs)
    return self:performAttack(playerEntity, AttackType.GRAB, {x = 0, y = 0}, ecs)
end

return CombatSystem 