-- save.lua - Sistema de Save/Load
-- Gerencia persistência de dados de metaprogressão

local SaveManager = {}

local saveFile = "slime_save.json"

-- Encoder/Decoder JSON simples
local function encodeJSON(data, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    
    if type(data) == "table" then
        local result = "{\n"
        local first = true
        for k, v in pairs(data) do
            if not first then
                result = result .. ",\n"
            end
            first = false
            result = result .. indentStr .. "  \"" .. tostring(k) .. "\": "
            result = result .. encodeJSON(v, indent + 1)
        end
        result = result .. "\n" .. indentStr .. "}"
        return result
    elseif type(data) == "string" then
        return "\"" .. data:gsub("\"", "\\\"") .. "\""
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "boolean" then
        return data and "true" or "false"
    else
        return "null"
    end
end

local function decodeJSON(str)
    -- Implementação simples de JSON decode
    -- Para produção, usar biblioteca como dkjson
    str = str:gsub("%s+", " ") -- Remove extra whitespace
    
    -- Hack simples para decodificar JSON básico
    -- Substitui true/false/null por equivalentes Lua
    str = str:gsub("true", "true")
    str = str:gsub("false", "false") 
    str = str:gsub("null", "nil")
    
    -- Remove aspas das chaves (hack)
    str = str:gsub('"([%w_]+)":', '%1=')
    
    -- Converte para sintaxe de tabela Lua
    str = str:gsub("{", "{")
    str = str:gsub("}", "}")
    str = str:gsub("%[", "{")
    str = str:gsub("%]", "}")
    
    -- Executa como código Lua (INSEGURO - apenas para prototipo!)
    local func = load("return " .. str)
    if func then
        return func()
    else
        return nil
    end
end

function SaveManager:save(gameConfig)
    local saveData = {
        version = "1.0",
        timestamp = os.time(),
        meta = gameConfig.meta,
        sage = gameConfig.sage,
        settings = {
            difficulty = gameConfig.difficulty,
            debug = gameConfig.debug
        },
        stats = {
            totalPlayTime = gameConfig.totalPlayTime or 0,
            highestLevel = gameConfig.highestLevel or 1,
            favoriteSkills = gameConfig.favoriteSkills or {}
        }
    }
    
    local jsonData = encodeJSON(saveData)
    local success = love.filesystem.write(saveFile, jsonData)
    
    if success then
        print("Jogo salvo com sucesso!")
        return true
    else
        print("Erro ao salvar o jogo!")
        return false
    end
end

function SaveManager:load()
    if not love.filesystem.getInfo(saveFile) then
        print("Arquivo de save não encontrado, criando novo jogo.")
        return nil
    end
    
    local jsonData = love.filesystem.read(saveFile)
    if not jsonData then
        print("Erro ao ler arquivo de save!")
        return nil
    end
    
    local saveData = decodeJSON(jsonData)
    if not saveData then
        print("Erro ao decodificar save data!")
        return nil
    end
    
    -- Validar versão
    if saveData.version ~= "1.0" then
        print("Versão de save incompatível: " .. (saveData.version or "unknown"))
        return nil
    end
    
    print("Save carregado com sucesso!")
    return saveData
end

function SaveManager:exists()
    return love.filesystem.getInfo(saveFile) ~= nil
end

function SaveManager:delete()
    local success = love.filesystem.remove(saveFile)
    if success then
        print("Save deletado!")
    else
        print("Erro ao deletar save!")
    end
    return success
end

function SaveManager:backup()
    if not self:exists() then
        return false
    end
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backupFile = "slime_save_backup_" .. timestamp .. ".json"
    
    local data = love.filesystem.read(saveFile)
    if data then
        local success = love.filesystem.write(backupFile, data)
        if success then
            print("Backup criado: " .. backupFile)
            return true
        end
    end
    
    print("Erro ao criar backup!")
    return false
end

function SaveManager:getDefaultSave()
    return {
        version = "1.0",
        timestamp = os.time(),
        meta = {
            techUnlocked = {},
            cityLevel = 0,
            runsCompleted = 0,
            totalEssence = 0
        },
        sage = {
            level = 1,
            hints = true,
            autoAnalysis = false
        },
        settings = {
            difficulty = "normal",
            debug = false
        },
        stats = {
            totalPlayTime = 0,
            highestLevel = 1,
            favoriteSkills = {}
        }
    }
end

-- Auto-save periódico
local autoSaveTimer = 0
local autoSaveInterval = 300 -- 5 minutos

function SaveManager:updateAutoSave(dt, gameConfig)
    autoSaveTimer = autoSaveTimer + dt
    
    if autoSaveTimer >= autoSaveInterval then
        autoSaveTimer = 0
        self:save(gameConfig)
        print("Auto-save realizado")
    end
end

return SaveManager 