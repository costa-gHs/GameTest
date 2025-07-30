-- enemy_ai_system.lua - IA Avançada para Inimigos
-- Estados comportamentais, coordenação e padrões específicos

local EnemyAI = {}
local RNG = require("src.core.rng")
local EventBus = require("src.core.eventbus")

-- Estados de IA
local AIState = {
    IDLE = "idle",
    PATROL = "patrol",
    ALERT = "alert",
    CHASE = "chase",
    ATTACK = "attack",
    RETREAT = "retreat",
    STUNNED = "stunned",
    DEAD = "dead"
}

-- Tipos de inimigo com comportamentos únicos
local EnemyTypes = {
    wanderer = {
        aggroRange = 80,
        attackRange = 25,
        moveSpeed = 50,
        health = 40,
        attackDamage = 15,
        behavior = "passive_aggressive"
    },
    guard = {
        aggroRange = 100,
        attackRange = 30,
        moveSpeed = 40,
        health = 80,
        attackDamage = 25,
        behavior = "defensive"
    },
    hunter = {
        aggroRange = 120,
        attackRange = 20,
        moveSpeed = 70,
        health = 30,
        attackDamage = 20,
        behavior = "aggressive"
    },
    mage = {
        aggroRange = 150,
        attackRange = 100,
        moveSpeed = 30,
        health = 25,
        attackDamage = 35,
        behavior = "ranged"
    }
}

function EnemyAI:addToECS(ecs)
    ecs:addSystem("enemy_ai", function(dt, ecsInstance)
        local enemies = ecsInstance:getEntitiesWith("AI", "Transform", "Health")
        
        for _, enemy in ipairs(enemies) do
            local ai = ecsInstance:getComponent(enemy, "AI")
            local transform = ecsInstance:getComponent(enemy, "Transform")
            local health = ecsInstance:getComponent(enemy, "Health")
            local velocity = ecsInstance:getComponent(enemy, "Velocity")
            local combat = ecsInstance:getComponent(enemy, "Combat")
            
            -- Verificar se está vivo
            if health.current <= 0 then
                if ai.state ~= AIState.DEAD then
                    self:transitionState(enemy, AIState.DEAD, ecsInstance)
                end
                continue
            end
            
            -- Atualizar timers
            self:updateTimers(ai, dt)
            
            -- Encontrar jogador mais próximo
            local player = self:findNearestPlayer(enemy, ecsInstance)
            local playerDistance = player and self:getDistance(transform, 
                ecsInstance:getComponent(player, "Transform")) or math.huge
            
            -- Máquina de estados
            self:updateStateMachine(enemy, ai, transform, velocity, combat, 
                                  player, playerDistance, dt, ecsInstance)
        end
    end, 25)
end

function EnemyAI:updateStateMachine(enemy, ai, transform, velocity, combat, 
                                   player, playerDistance, dt, ecs)
    local enemyConfig = EnemyTypes[ai.type] or EnemyTypes.wanderer
    
    if ai.state == AIState.IDLE then
        self:handleIdleState(enemy, ai, enemyConfig, player, playerDistance, ecs)
    elseif ai.state == AIState.PATROL then
        self:handlePatrolState(enemy, ai, transform, velocity, enemyConfig, 
                              player, playerDistance, dt, ecs)
    elseif ai.state == AIState.ALERT then
        self:handleAlertState(enemy, ai, transform, velocity, enemyConfig, 
                             player, playerDistance, dt, ecs)
    elseif ai.state == AIState.CHASE then
        self:handleChaseState(enemy, ai, transform, velocity, combat, enemyConfig, 
                             player, playerDistance, dt, ecs)
    elseif ai.state == AIState.ATTACK then
        self:handleAttackState(enemy, ai, transform, velocity, combat, enemyConfig, 
                              player, playerDistance, dt, ecs)
    elseif ai.state == AIState.RETREAT then
        self:handleRetreatState(enemy, ai, transform, velocity, enemyConfig, 
                               player, playerDistance, dt, ecs)
    elseif ai.state == AIState.STUNNED then
        self:handleStunnedState(enemy, ai, dt, ecs)
    end
end

function EnemyAI:handleIdleState(enemy, ai, config, player, playerDistance, ecs)
    -- Detectar jogador
    if player and playerDistance < config.aggroRange then
        self:transitionState(enemy, AIState.ALERT, ecs)
        ai.target = player
        ai.alertTimer = 1.0 -- Tempo para processar ameaça
        return
    end
    
    -- Comportamento idle baseado no tipo
    if config.behavior == "passive_aggressive" then
        -- Wanderer: movimento aleatório ocasional
        if not ai.idleTimer or ai.idleTimer <= 0 then
            if RNG:randomBool(0.3) then
                self:transitionState(enemy, AIState.PATROL, ecs)
                ai.patrolTarget = self:generateRandomPatrolPoint(enemy, ecs)
            end
            ai.idleTimer = RNG:randomFloat(2, 5)
        end
    elseif config.behavior == "defensive" then
        -- Guard: permanecer parado, mas vigilante
        ai.alertRadius = config.aggroRange * 1.2
    end
end

function EnemyAI:handlePatrolState(enemy, ai, transform, velocity, config, 
                                  player, playerDistance, dt, ecs)
    -- Verificar ameaças durante patrulha
    if player and playerDistance < config.aggroRange then
        self:transitionState(enemy, AIState.ALERT, ecs)
        ai.target = player
        return
    end
    
    -- Mover em direção ao ponto de patrulha
    if ai.patrolTarget then
        local dx = ai.patrolTarget.x - transform.x
        local dy = ai.patrolTarget.y - transform.y
        local distance = math.sqrt(dx * dx + dy * dy)
        
        if distance > 10 then
            -- Mover em direção ao alvo
            velocity.vx = (dx / distance) * config.moveSpeed * 0.5
            velocity.vy = (dy / distance) * config.moveSpeed * 0.5
        else
            -- Chegou ao destino
            self:transitionState(enemy, AIState.IDLE, ecs)
            ai.patrolTarget = nil
            ai.idleTimer = RNG:randomFloat(1, 3)
        end
    else
        self:transitionState(enemy, AIState.IDLE, ecs)
    end
end

function EnemyAI:handleAlertState(enemy, ai, transform, velocity, config, 
                                 player, playerDistance, dt, ecs)
    -- Parar movimento
    velocity.vx = velocity.vx * 0.5
    velocity.vy = velocity.vy * 0.5
    
    -- Olhar para o jogador
    if player then
        local playerTransform = ecs:getComponent(player, "Transform")
        ai.lookDirection = {
            x = playerTransform.x - transform.x,
            y = playerTransform.y - transform.y
        }
    end
    
    ai.alertTimer = ai.alertTimer - dt
    
    if ai.alertTimer <= 0 then
        if player and playerDistance < config.aggroRange * 1.5 then
            -- Iniciar perseguição
            self:transitionState(enemy, AIState.CHASE, ecs)
        else
            -- Falso alarme - voltar ao idle
            self:transitionState(enemy, AIState.IDLE, ecs)
            ai.target = nil
        end
    end
end

function EnemyAI:handleChaseState(enemy, ai, transform, velocity, combat, config, 
                                 player, playerDistance, dt, ecs)
    if not player then
        self:transitionState(enemy, AIState.IDLE, ecs)
        return
    end
    
    -- Perder o jogador se muito distante
    if playerDistance > config.aggroRange * 2 then
        self:transitionState(enemy, AIState.IDLE, ecs)
        ai.target = nil
        return
    end
    
    -- Atacar se próximo o suficiente
    if playerDistance < config.attackRange then
        self:transitionState(enemy, AIState.ATTACK, ecs)
        return
    end
    
    -- Perseguir jogador
    local playerTransform = ecs:getComponent(player, "Transform")
    local dx = playerTransform.x - transform.x
    local dy = playerTransform.y - transform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > 0 then
        -- Comportamento específico por tipo
        if config.behavior == "aggressive" then
            -- Hunter: perseguição direta e rápida
            velocity.vx = (dx / distance) * config.moveSpeed
            velocity.vy = (dy / distance) * config.moveSpeed
        elseif config.behavior == "defensive" then
            -- Guard: aproximação cautelosa
            velocity.vx = (dx / distance) * config.moveSpeed * 0.7
            velocity.vy = (dy / distance) * config.moveSpeed * 0.7
        elseif config.behavior == "ranged" then
            -- Mage: manter distância ideal
            local idealDistance = config.attackRange * 0.8
            if playerDistance > idealDistance then
                velocity.vx = (dx / distance) * config.moveSpeed * 0.6
                velocity.vy = (dy / distance) * config.moveSpeed * 0.6
            else
                -- Manter distância
                velocity.vx = -(dx / distance) * config.moveSpeed * 0.3
                velocity.vy = -(dy / distance) * config.moveSpeed * 0.3
            end
        else
            -- Comportamento padrão
            velocity.vx = (dx / distance) * config.moveSpeed * 0.8
            velocity.vy = (dy / distance) * config.moveSpeed * 0.8
        end
        
        -- Pathfinding básico - evitar obstáculos
        if not self:canMoveTowards(transform, playerTransform, ecs) then
            self:avoidObstacles(transform, velocity, dx, dy, config.moveSpeed, ecs)
        end
    end
end

function EnemyAI:handleAttackState(enemy, ai, transform, velocity, combat, config, 
                                  player, playerDistance, dt, ecs)
    -- Parar movimento durante ataque
    velocity.vx = velocity.vx * 0.1
    velocity.vy = velocity.vy * 0.1
    
    if not player then
        self:transitionState(enemy, AIState.IDLE, ecs)
        return
    end
    
    -- Verificar se ainda está no range
    if playerDistance > config.attackRange * 1.2 then
        self:transitionState(enemy, AIState.CHASE, ecs)
        return
    end
    
    -- Executar ataque baseado no tipo
    if not ai.attackTimer or ai.attackTimer <= 0 then
        self:executeAttack(enemy, ai, transform, combat, config, player, ecs)
        ai.attackTimer = self:getAttackCooldown(config)
    end
    
    -- Voltar para chase após ataque
    if ai.attackTimer and ai.attackTimer <= ai.attackCooldown * 0.5 then
        if config.behavior == "aggressive" then
            self:transitionState(enemy, AIState.CHASE, ecs)
        else
            self:transitionState(enemy, AIState.RETREAT, ecs)
            ai.retreatTimer = 1.0
        end
    end
end

function EnemyAI:handleRetreatState(enemy, ai, transform, velocity, config, 
                                   player, playerDistance, dt, ecs)
    if not player then
        self:transitionState(enemy, AIState.IDLE, ecs)
        return
    end
    
    -- Recuar do jogador
    local playerTransform = ecs:getComponent(player, "Transform")
    local dx = transform.x - playerTransform.x
    local dy = transform.y - playerTransform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance > 0 then
        velocity.vx = (dx / distance) * config.moveSpeed * 0.6
        velocity.vy = (dy / distance) * config.moveSpeed * 0.6
    end
    
    ai.retreatTimer = ai.retreatTimer - dt
    
    if ai.retreatTimer <= 0 or playerDistance > config.attackRange * 1.5 then
        self:transitionState(enemy, AIState.CHASE, ecs)
    end
end

function EnemyAI:handleStunnedState(enemy, ai, dt, ecs)
    ai.stunTimer = ai.stunTimer - dt
    
    if ai.stunTimer <= 0 then
        self:transitionState(enemy, AIState.IDLE, ecs)
    end
end

function EnemyAI:executeAttack(enemy, ai, transform, combat, config, player, ecs)
    local playerTransform = ecs:getComponent(player, "Transform")
    
    if config.behavior == "ranged" then
        -- Mage: ataque à distância
        self:createProjectile(enemy, transform, playerTransform, config, ecs)
    else
        -- Ataque corpo a corpo
        if combat then
            combat.state = "attacking"
            combat.attackDirection = {
                x = playerTransform.x - transform.x,
                y = playerTransform.y - transform.y
            }
            combat.stateTimer = 0.3
        end
    end
    
    EventBus:emit("enemy:attacked", {
        enemy = enemy,
        target = player,
        attackType = config.behavior
    })
end

function EnemyAI:createProjectile(enemy, transform, playerTransform, config, ecs)
    -- Criar projétil
    local projectile = ecs:createEntity()
    
    local dx = playerTransform.x - transform.x
    local dy = playerTransform.y - transform.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    ecs:addComponent(projectile, "Transform", {
        x = transform.x,
        y = transform.y,
        rotation = math.atan2(dy, dx),
        scale = 1
    })
    
    ecs:addComponent(projectile, "Velocity", {
        vx = (dx / distance) * 200,
        vy = (dy / distance) * 200,
        maxSpeed = 200
    })
    
    ecs:addComponent(projectile, "Sprite", {
        color = {0.8, 0.3, 0.8, 1},
        size = 6
    })
    
    ecs:addComponent(projectile, "Collider", {
        radius = 3,
        trigger = true
    })
    
    ecs:addComponent(projectile, "Lifetime", {
        remaining = 3.0
    })
    
    ecs:addComponent(projectile, "Projectile", {
        damage = config.attackDamage,
        owner = enemy
    })
end

-- Funções auxiliares
function EnemyAI:transitionState(enemy, newState, ecs)
    local ai = ecs:getComponent(enemy, "AI")
    if ai then
        ai.previousState = ai.state
        ai.state = newState
        ai.stateTimer = 0
    end
end

function EnemyAI:updateTimers(ai, dt)
    if ai.idleTimer then ai.idleTimer = ai.idleTimer - dt end
    if ai.alertTimer then ai.alertTimer = ai.alertTimer - dt end
    if ai.attackTimer then ai.attackTimer = ai.attackTimer - dt end
    if ai.retreatTimer then ai.retreatTimer = ai.retreatTimer - dt end
    if ai.stunTimer then ai.stunTimer = ai.stunTimer - dt end
    ai.stateTimer = ai.stateTimer + dt
end

function EnemyAI:findNearestPlayer(enemy, ecs)
    local players = ecs:getEntitiesWith("SlimeCore", "Transform")
    if #players == 0 then return nil end
    
    local enemyTransform = ecs:getComponent(enemy, "Transform")
    local nearest = nil
    local nearestDistance = math.huge
    
    for _, player in ipairs(players) do
        local playerTransform = ecs:getComponent(player, "Transform")
        local distance = self:getDistance(enemyTransform, playerTransform)
        
        if distance < nearestDistance then
            nearest = player
            nearestDistance = distance
        end
    end
    
    return nearest
end

function EnemyAI:getDistance(transformA, transformB)
    local dx = transformB.x - transformA.x
    local dy = transformB.y - transformA.y
    return math.sqrt(dx * dx + dy * dy)
end

function EnemyAI:generateRandomPatrolPoint(enemy, ecs)
    local transform = ecs:getComponent(enemy, "Transform")
    local angle = RNG:randomFloat(0, 2 * math.pi)
    local distance = RNG:randomFloat(50, 150)
    
    return {
        x = transform.x + math.cos(angle) * distance,
        y = transform.y + math.sin(angle) * distance
    }
end

function EnemyAI:canMoveTowards(fromTransform, toTransform, ecs)
    -- Pathfinding simples - verificar se há parede no caminho
    -- Implementação básica - pode ser expandida
    return true
end

function EnemyAI:avoidObstacles(transform, velocity, targetDx, targetDy, speed, ecs)
    -- Algoritmo simples de evasão de obstáculos
    local avoidanceAngle = math.pi / 4 -- 45 graus
    local originalAngle = math.atan2(targetDy, targetDx)
    
    -- Tentar direções alternativas
    for _, direction in ipairs({avoidanceAngle, -avoidanceAngle}) do
        local newAngle = originalAngle + direction
        velocity.vx = math.cos(newAngle) * speed * 0.6
        velocity.vy = math.sin(newAngle) * speed * 0.6
        break
    end
end

function EnemyAI:getAttackCooldown(config)
    if config.behavior == "aggressive" then
        return 1.0
    elseif config.behavior == "defensive" then
        return 2.0
    elseif config.behavior == "ranged" then
        return 1.5
    else
        return 1.5
    end
end

return EnemyAI