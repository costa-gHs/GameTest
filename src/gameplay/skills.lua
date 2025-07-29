-- skills.lua - Sistema de Evolução de Habilidades
-- Traços, Habilidades Únicas, Ultimate Skills e sistema de craft/fusão

local SkillSystem = {}
local EventBus = require("src.core.eventbus")
local RNG = require("src.core.rng")

-- Raridades
local Rarity = {
    COMMON = "common",
    UNCOMMON = "uncommon", 
    RARE = "rare",
    EPIC = "epic",
    LEGENDARY = "legendary",
    ULTIMATE = "ultimate"
}

-- Tipos de habilidade
local SkillType = {
    TRAIT = "trait",           -- Passivo permanente
    UNIQUE = "unique",         -- Habilidade ativa especial
    ULTIMATE = "ultimate",     -- Poder supremo
    FORM = "form"             -- Transformação
}

function SkillSystem:new(config)
    local ss = {}
    setmetatable(ss, { __index = self })
    
    ss.config = config
    ss.skillDatabase = {}
    ss.evolutionRules = {}
    ss.craftingRecipes = {}
    
    -- Inicializar database
    ss:initializeSkillDatabase()
    ss:initializeEvolutionRules()
    ss:initializeCraftingRecipes()
    
    return ss
end

function SkillSystem:initializeSkillDatabase()
    self.skillDatabase = {
        -- =================================
        -- TRAÇOS BÁSICOS (20+)
        -- =================================
        
        -- Combate
        basic_combat = {
            id = "basic_combat",
            name = "Combate Básico",
            type = SkillType.TRAIT,
            rarity = Rarity.COMMON,
            description = "Conhecimento fundamental de combate",
            effects = { attack_damage = 1.1 },
            category = "combat"
        },
        
        warrior_instinct = {
            id = "warrior_instinct",
            name = "Instinto Guerreiro",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Reduz cooldown de ataques e melhora precisão",
            effects = { attack_speed = 1.2, accuracy = 1.1 },
            category = "combat"
        },
        
        berserker_rage = {
            id = "berserker_rage",
            name = "Fúria Berserker",
            type = SkillType.TRAIT,
            rarity = Rarity.RARE,
            description = "Dano aumenta conforme vida diminui",
            effects = { rage_damage = true },
            category = "combat"
        },
        
        defensive_stance = {
            id = "defensive_stance",
            name = "Postura Defensiva",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Reduz dano recebido quando parado",
            effects = { damage_reduction = 0.15, defense_bonus = true },
            category = "defense"
        },
        
        iron_skin = {
            id = "iron_skin",
            name = "Pele de Ferro",
            type = SkillType.TRAIT,
            rarity = Rarity.RARE,
            description = "Resistência física massiva",
            effects = { physical_resistance = 0.3, max_health = 1.2 },
            category = "defense"
        },
        
        -- Movimento
        fast_movement = {
            id = "fast_movement",
            name = "Movimento Rápido",
            type = SkillType.TRAIT,
            rarity = Rarity.COMMON,
            description = "Velocidade de movimento aumentada",
            effects = { movement_speed = 1.2 },
            category = "movement"
        },
        
        dash_master = {
            id = "dash_master",
            name = "Mestre do Dash",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Dash mais rápido e com menor cooldown",
            effects = { dash_speed = 1.3, dash_cooldown = 0.7 },
            category = "movement"
        },
        
        phase_walk = {
            id = "phase_walk",
            name = "Caminhada Fantasma",
            type = SkillType.TRAIT,
            rarity = Rarity.EPIC,
            description = "Atravessa inimigos durante dash",
            effects = { dash_phasing = true },
            category = "movement"
        },
        
        windwalk = {
            id = "windwalk",
            name = "Passo do Vento",
            type = SkillType.TRAIT,
            rarity = Rarity.RARE,
            description = "Deixa rastro de vento que acelera aliados",
            effects = { wind_trail = true, movement_speed = 1.15 },
            category = "movement"
        },
        
        -- Utilidade
        essence_affinity = {
            id = "essence_affinity",
            name = "Afinidade com Essência",
            type = SkillType.TRAIT,
            rarity = Rarity.COMMON,
            description = "Melhora absorção de essência",
            effects = { essence_gain = 1.2 },
            category = "utility"
        },
        
        predator_senses = {
            id = "predator_senses",
            name = "Sentidos Predadores",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Aumenta range de detecção e predação",
            effects = { detection_range = 1.5, predation_range = 1.3 },
            category = "utility"
        },
        
        analysis_boost = {
            id = "analysis_boost",
            name = "Análise Acelerada",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Processa análises mais rapidamente",
            effects = { analysis_speed = 2.0 },
            category = "utility"
        },
        
        -- Regeneração/Sobrevivência
        natural_regeneration = {
            id = "natural_regeneration",
            name = "Regeneração Natural",
            type = SkillType.TRAIT,
            rarity = Rarity.COMMON,
            description = "Regenera HP lentamente ao longo do tempo",
            effects = { health_regen = 0.5 },
            category = "survival"
        },
        
        battle_recovery = {
            id = "battle_recovery",
            name = "Recuperação de Batalha",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Regenera HP ao derrotar inimigos",
            effects = { kill_heal = 15 },
            category = "survival"
        },
        
        undying_will = {
            id = "undying_will",
            name = "Vontade Imortal",
            type = SkillType.TRAIT,
            rarity = Rarity.EPIC,
            description = "Sobrevive a golpes fatais uma vez por combate",
            effects = { death_save = true },
            category = "survival"
        },
        
        -- Mágico/Especial
        crystalline_structure = {
            id = "crystalline_structure",
            name = "Estrutura Cristalina",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Resistência mágica e eficiência de mana",
            effects = { magic_resistance = 0.2, mana_efficiency = 1.2 },
            category = "magic"
        },
        
        mana_overflow = {
            id = "mana_overflow",
            name = "Transbordamento de Mana",
            type = SkillType.TRAIT,
            rarity = Rarity.RARE,
            description = "Excesso de mana é convertido em dano",
            effects = { mana_damage = true },
            category = "magic"
        },
        
        storm_affinity = {
            id = "storm_affinity",
            name = "Afinidade Temporal",
            type = SkillType.TRAIT,
            rarity = Rarity.EPIC,
            description = "Ataques têm chance de causar tempestades",
            effects = { storm_proc = 0.15 },
            category = "magic"
        },
        
        -- Furtividade
        stealth = {
            id = "stealth",
            name = "Furtividade",
            type = SkillType.TRAIT,
            rarity = Rarity.UNCOMMON,
            description = "Reduz detecção por inimigos",
            effects = { stealth_bonus = 0.3, detection_reduction = 0.5 },
            category = "stealth"
        },
        
        shadow_step = {
            id = "shadow_step",
            name = "Passo Sombrio",
            type = SkillType.TRAIT,
            rarity = Rarity.RARE,
            description = "Dash não quebra invisibilidade",
            effects = { stealth_dash = true },
            category = "stealth"
        },
        
        assassinate = {
            id = "assassinate",
            name = "Assassinato",
            type = SkillType.TRAIT,
            rarity = Rarity.EPIC,
            description = "Ataques furtivos causam dano crítico massivo",
            effects = { stealth_crit = 3.0 },
            category = "stealth"
        },
        
        -- =================================
        -- HABILIDADES ÚNICAS (6)
        -- =================================
        
        gluttony = {
            id = "gluttony",
            name = "Gula",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Predação à distância com canalização reduzida",
            effects = { 
                range_predation = true,
                predation_speed = 2.0,
                multi_predation = 3
            },
            cooldown = 30,
            category = "unique"
        },
        
        absolute_barrier = {
            id = "absolute_barrier",
            name = "Barreira Absoluta",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Imunidade total por tempo limitado",
            effects = { 
                immunity_duration = 5.0,
                barrier_reflect = true
            },
            cooldown = 60,
            category = "unique"
        },
        
        storm_magic = {
            id = "storm_magic",
            name = "Magia de Tempestade",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Invoca tempestade que danifica área",
            effects = {
                storm_damage = 80,
                storm_radius = 120,
                storm_duration = 8.0
            },
            cooldown = 45,
            category = "unique"
        },
        
        time_manipulation = {
            id = "time_manipulation",
            name = "Manipulação Temporal",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Desacelera tempo ao redor, acelera próprio tempo",
            effects = {
                time_slow_factor = 0.3,
                self_speed_boost = 2.0,
                duration = 6.0
            },
            cooldown = 90,
            category = "unique"
        },
        
        soul_devour = {
            id = "soul_devour",
            name = "Devorar Alma",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Absorve completamente inimigo, ganhando suas habilidades",
            effects = {
                complete_absorption = true,
                skill_steal = true,
                permanent_gain = true
            },
            cooldown = 120,
            category = "unique"
        },
        
        reality_slice = {
            id = "reality_slice",
            name = "Corte da Realidade",
            type = SkillType.UNIQUE,
            rarity = Rarity.LEGENDARY,
            description = "Ataque que ignora todas as defesas e barreiras",
            effects = {
                ignore_defense = true,
                ignore_barriers = true,
                true_damage = 200
            },
            cooldown = 75,
            category = "unique"
        },
        
        -- =================================
        -- ULTIMATE SKILLS (1 Protótipo)
        -- =================================
        
        wisdom_king_raphael = {
            id = "wisdom_king_raphael",
            name = "Rei da Sabedoria: Raphael",
            type = SkillType.ULTIMATE,
            rarity = Rarity.ULTIMATE,
            description = "Transcende limitações, controle absoluto sobre análise e predição",
            effects = {
                omniscience = true,
                auto_analysis = true,
                perfect_prediction = true,
                skill_synthesis = true,
                reality_manipulation = 0.1
            },
            subskills = {
                "Future_Sight", "All_Analysis", "Skill_Creation", "Law_Manipulation"
            },
            requirements = {
                sage_level = 3,
                unique_skills = 3,
                total_essence = 10000
            },
            category = "ultimate"
        }
    }
end

function SkillSystem:initializeEvolutionRules()
    self.evolutionRules = {
        -- Traços básicos podem evoluir
        {
            from = {"basic_combat", "warrior_instinct"},
            to = "berserker_rage",
            requirements = { combat_kills = 50 }
        },
        
        {
            from = {"fast_movement", "dash_master"},
            to = "phase_walk",
            requirements = { distance_traveled = 10000 }
        },
        
        {
            from = {"natural_regeneration", "battle_recovery"},
            to = "undying_will",
            requirements = { times_near_death = 5 }
        },
        
        {
            from = {"stealth", "shadow_step"},
            to = "assassinate",
            requirements = { stealth_kills = 20 }
        },
        
        -- Habilidades Únicas podem ser desbloqueadas
        {
            from = {"predator_senses", "essence_affinity", "analysis_boost"},
            to = "gluttony",
            requirements = { 
                successful_predations = 100,
                traits_discovered = 20
            }
        },
        
        {
            from = {"defensive_stance", "iron_skin", "crystalline_structure"},
            to = "absolute_barrier",
            requirements = { 
                damage_blocked = 5000,
                perfect_defenses = 10
            }
        },
        
        {
            from = {"storm_affinity", "mana_overflow", "crystalline_structure"},
            to = "storm_magic",
            requirements = {
                magic_damage_dealt = 2000,
                storm_procs = 50
            }
        },
        
        -- Ultimate requer múltiplas Unique
        {
            from = {"gluttony", "absolute_barrier", "storm_magic"},
            to = "wisdom_king_raphael",
            requirements = {
                sage_level = 3,
                total_essence = 10000,
                mastery_level = 100
            }
        }
    }
end

function SkillSystem:initializeCraftingRecipes()
    self.craftingRecipes = {
        -- Fusões de traços
        {
            id = "warrior_fusion",
            name = "Fusão do Guerreiro",
            ingredients = {
                {type = "trait", id = "basic_combat", quantity = 1},
                {type = "trait", id = "defensive_stance", quantity = 1}
            },
            result = {
                type = "trait",
                id = "warrior_instinct"
            },
            essence_cost = 50
        },
        
        {
            id = "speed_fusion",
            name = "Fusão da Velocidade",
            ingredients = {
                {type = "trait", id = "fast_movement", quantity = 1},
                {type = "essence", quantity = 100}
            },
            result = {
                type = "trait",
                id = "dash_master"
            },
            essence_cost = 75
        },
        
        {
            id = "magic_synthesis",
            name = "Síntese Mágica",
            ingredients = {
                {type = "trait", id = "crystalline_structure", quantity = 1},
                {type = "trait", id = "mana_overflow", quantity = 1},
                {type = "essence", quantity = 200}
            },
            result = {
                type = "trait",
                id = "storm_affinity"
            },
            essence_cost = 150
        },
        
        -- Criação de habilidades únicas
        {
            id = "create_soul_devour",
            name = "Criação: Devorar Alma",
            ingredients = {
                {type = "trait", id = "predator_senses", quantity = 1},
                {type = "trait", id = "essence_affinity", quantity = 1},
                {type = "unique", id = "gluttony", quantity = 1},
                {type = "essence", quantity = 500}
            },
            result = {
                type = "unique",
                id = "soul_devour"
            },
            essence_cost = 1000
        }
    }
end

-- Verificar evoluções disponíveis
function SkillSystem:checkEvolutions(slimeEntity, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore or not slimeCore.traits then return {} end
    
    local availableEvolutions = {}
    local playerStats = self:getPlayerStats(slimeEntity, ecs)
    
    for _, rule in ipairs(self.evolutionRules) do
        if self:canEvolve(slimeCore, rule, playerStats) then
            table.insert(availableEvolutions, {
                rule = rule,
                result = self.skillDatabase[rule.to]
            })
        end
    end
    
    return availableEvolutions
end

function SkillSystem:canEvolve(slimeCore, rule, playerStats)
    -- Verificar se tem os traços necessários
    local hasAllFrom = true
    for _, requiredId in ipairs(rule.from) do
        local hasSkill = false
        for _, trait in ipairs(slimeCore.traits or {}) do
            if trait.id == requiredId then
                hasSkill = true
                break
            end
        end
        if not hasSkill then
            hasAllFrom = false
            break
        end
    end
    
    if not hasAllFrom then return false end
    
    -- Verificar requisitos estatísticos
    for req, value in pairs(rule.requirements or {}) do
        if not playerStats[req] or playerStats[req] < value then
            return false
        end
    end
    
    return true
end

function SkillSystem:performEvolution(slimeEntity, evolution, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore then return false end
    
    local newSkill = self.skillDatabase[evolution.rule.to]
    if not newSkill then return false end
    
    -- Remover traços utilizados na evolução
    for _, usedId in ipairs(evolution.rule.from) do
        for i = #slimeCore.traits, 1, -1 do
            if slimeCore.traits[i].id == usedId then
                table.remove(slimeCore.traits, i)
                break
            end
        end
    end
    
    -- Adicionar nova habilidade
    if newSkill.type == SkillType.TRAIT then
        if not slimeCore.traits then slimeCore.traits = {} end
        table.insert(slimeCore.traits, newSkill)
    elseif newSkill.type == SkillType.UNIQUE then
        if not slimeCore.uniqueSkills then slimeCore.uniqueSkills = {} end
        table.insert(slimeCore.uniqueSkills, newSkill)
    elseif newSkill.type == SkillType.ULTIMATE then
        if not slimeCore.ultimateSkills then slimeCore.ultimateSkills = {} end
        table.insert(slimeCore.ultimateSkills, newSkill)
    end
    
    EventBus:emit("skill:evolved", {
        slime = slimeEntity,
        newSkill = newSkill,
        usedSkills = evolution.rule.from
    })
    
    print("EVOLUÇÃO: " .. newSkill.name .. " (" .. newSkill.rarity .. ")")
    return true
end

-- Sistema de Craft
function SkillSystem:getAvailableRecipes(slimeEntity, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore then return {} end
    
    local availableRecipes = {}
    
    for _, recipe in ipairs(self.craftingRecipes) do
        if self:canCraft(slimeCore, recipe) then
            table.insert(availableRecipes, recipe)
        end
    end
    
    return availableRecipes
end

function SkillSystem:canCraft(slimeCore, recipe)
    -- Verificar essência suficiente
    if slimeCore.essence < recipe.essence_cost then
        return false
    end
    
    -- Verificar ingredientes
    for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "trait" then
            local hasIngredient = false
            for _, trait in ipairs(slimeCore.traits or {}) do
                if trait.id == ingredient.id then
                    hasIngredient = true
                    break
                end
            end
            if not hasIngredient then return false end
        elseif ingredient.type == "unique" then
            local hasIngredient = false
            for _, skill in ipairs(slimeCore.uniqueSkills or {}) do
                if skill.id == ingredient.id then
                    hasIngredient = true
                    break
                end
            end
            if not hasIngredient then return false end
        elseif ingredient.type == "essence" then
            if slimeCore.essence < ingredient.quantity then
                return false
            end
        end
    end
    
    return true
end

function SkillSystem:craftSkill(slimeEntity, recipe, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore or not self:canCraft(slimeCore, recipe) then
        return false, "Não pode criar esta habilidade"
    end
    
    -- Consumir ingredientes
    for _, ingredient in ipairs(recipe.ingredients) do
        if ingredient.type == "trait" then
            for i = #slimeCore.traits, 1, -1 do
                if slimeCore.traits[i].id == ingredient.id then
                    table.remove(slimeCore.traits, i)
                    break
                end
            end
        elseif ingredient.type == "unique" then
            for i = #(slimeCore.uniqueSkills or {}), 1, -1 do
                if slimeCore.uniqueSkills[i].id == ingredient.id then
                    table.remove(slimeCore.uniqueSkills, i)
                    break
                end
            end
        elseif ingredient.type == "essence" then
            slimeCore.essence = slimeCore.essence - ingredient.quantity
        end
    end
    
    -- Consumir essência de craft
    slimeCore.essence = slimeCore.essence - recipe.essence_cost
    
    -- Criar resultado
    local resultSkill = self.skillDatabase[recipe.result.id]
    if resultSkill then
        if resultSkill.type == SkillType.TRAIT then
            if not slimeCore.traits then slimeCore.traits = {} end
            table.insert(slimeCore.traits, resultSkill)
        elseif resultSkill.type == SkillType.UNIQUE then
            if not slimeCore.uniqueSkills then slimeCore.uniqueSkills = {} end
            table.insert(slimeCore.uniqueSkills, resultSkill)
        end
        
        EventBus:emit("skill:crafted", {
            slime = slimeEntity,
            recipe = recipe,
            result = resultSkill
        })
        
        print("CRAFT: " .. resultSkill.name .. " criado!")
        return true, "Habilidade criada: " .. resultSkill.name
    end
    
    return false, "Erro ao criar habilidade"
end

-- Usar habilidade única
function SkillSystem:useUniqueSkill(slimeEntity, skillId, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore or not slimeCore.uniqueSkills then
        return false, "Nenhuma habilidade única disponível"
    end
    
    local skill = nil
    for _, s in ipairs(slimeCore.uniqueSkills) do
        if s.id == skillId then
            skill = s
            break
        end
    end
    
    if not skill then
        return false, "Habilidade não encontrada"
    end
    
    -- Verificar cooldown
    if skill.lastUsed and love.timer.getTime() - skill.lastUsed < skill.cooldown then
        return false, "Habilidade em cooldown"
    end
    
    -- Executar efeito da habilidade
    self:executeUniqueSkill(slimeEntity, skill, ecs)
    
    skill.lastUsed = love.timer.getTime()
    
    EventBus:emit("skill:used", {
        slime = slimeEntity,
        skill = skill
    })
    
    return true, "Habilidade usada: " .. skill.name
end

function SkillSystem:executeUniqueSkill(slimeEntity, skill, ecs)
    local effects = skill.effects
    
    if skill.id == "gluttony" then
        -- Predação múltipla à distância
        self:executeGluttony(slimeEntity, effects, ecs)
    elseif skill.id == "absolute_barrier" then
        -- Barreira de imunidade
        self:executeAbsoluteBarrier(slimeEntity, effects, ecs)
    elseif skill.id == "storm_magic" then
        -- Tempestade de área
        self:executeStormMagic(slimeEntity, effects, ecs)
    end
end

function SkillSystem:executeGluttony(slimeEntity, effects, ecs)
    -- Implementar predação múltipla
    local transform = ecs:getComponent(slimeEntity, "Transform")
    if not transform then return end
    
    local targets = self:findNearbyTargets(slimeEntity, 100, ecs)
    local maxTargets = effects.multi_predation or 3
    
    for i = 1, math.min(#targets, maxTargets) do
        -- Simular predação instantânea
        EventBus:emit("predation:forced", {
            slime = slimeEntity,
            target = targets[i]
        })
    end
    
    print("GULA ativada: " .. math.min(#targets, maxTargets) .. " alvos devorados!")
end

function SkillSystem:executeAbsoluteBarrier(slimeEntity, effects, ecs)
    local combat = ecs:getComponent(slimeEntity, "Combat")
    if combat then
        combat.absoluteImmunity = love.timer.getTime() + effects.immunity_duration
        combat.barrierReflect = effects.barrier_reflect
    end
    
    print("BARREIRA ABSOLUTA ativada!")
end

function SkillSystem:executeStormMagic(slimeEntity, effects, ecs)
    local transform = ecs:getComponent(slimeEntity, "Transform")
    if not transform then return end
    
    -- Criar área de tempestade
    EventBus:emit("world:storm_created", {
        x = transform.x,
        y = transform.y,
        radius = effects.storm_radius,
        damage = effects.storm_damage,
        duration = effects.storm_duration
    })
    
    print("MAGIA DE TEMPESTADE ativada!")
end

-- Estatísticas do jogador para evoluções
function SkillSystem:getPlayerStats(slimeEntity, ecs)
    local slimeCore = ecs:getComponent(slimeEntity, "SlimeCore")
    if not slimeCore then return {} end
    
    return {
        combat_kills = slimeCore.stats and slimeCore.stats.kills or 0,
        distance_traveled = slimeCore.stats and slimeCore.stats.distance or 0,
        times_near_death = slimeCore.stats and slimeCore.stats.nearDeaths or 0,
        stealth_kills = slimeCore.stats and slimeCore.stats.stealthKills or 0,
        successful_predations = slimeCore.stats and slimeCore.stats.predations or 0,
        traits_discovered = slimeCore.traits and #slimeCore.traits or 0,
        damage_blocked = slimeCore.stats and slimeCore.stats.damageBlocked or 0,
        perfect_defenses = slimeCore.stats and slimeCore.stats.perfectDefenses or 0,
        magic_damage_dealt = slimeCore.stats and slimeCore.stats.magicDamage or 0,
        storm_procs = slimeCore.stats and slimeCore.stats.stormProcs or 0,
        sage_level = slimeCore.sageLevel or 1,
        total_essence = slimeCore.totalEssenceGained or 0,
        mastery_level = slimeCore.masteryLevel or 0
    }
end

function SkillSystem:findNearbyTargets(slimeEntity, range, ecs)
    local transform = ecs:getComponent(slimeEntity, "Transform")
    if not transform then return {} end
    
    local targets = {}
    local entities = ecs:getEntitiesWith("Transform")
    
    for _, entity in ipairs(entities) do
        if entity ~= slimeEntity then
            local entityTransform = ecs:getComponent(entity, "Transform")
            local dx = entityTransform.x - transform.x
            local dy = entityTransform.y - transform.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            if distance <= range then
                table.insert(targets, entity)
            end
        end
    end
    
    return targets
end

-- Interface pública
function SkillSystem:getSkillByCategory(category)
    local skills = {}
    for _, skill in pairs(self.skillDatabase) do
        if skill.category == category then
            table.insert(skills, skill)
        end
    end
    return skills
end

function SkillSystem:getSkillById(id)
    return self.skillDatabase[id]
end

function SkillSystem:getAllUniqueSkills()
    local uniques = {}
    for _, skill in pairs(self.skillDatabase) do
        if skill.type == SkillType.UNIQUE then
            table.insert(uniques, skill)
        end
    end
    return uniques
end

function SkillSystem:getAllUltimateSkills()
    local ultimates = {}
    for _, skill in pairs(self.skillDatabase) do
        if skill.type == SkillType.ULTIMATE then
            table.insert(ultimates, skill)
        end
    end
    return ultimates
end

return SkillSystem 