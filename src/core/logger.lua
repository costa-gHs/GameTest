-- logger.lua - Sistema de logging para debug

local Logger = {}

-- Configurações do logger
local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local currentLevel = LOG_LEVELS.DEBUG
local logHistory = {}
local maxHistory = 100

-- Função para adicionar log
function Logger:log(level, message, data)
    if level < currentLevel then return end
    
    local timestamp = os.date("%H:%M:%S")
    local logEntry = {
        timestamp = timestamp,
        level = level,
        message = message,
        data = data
    }
    
    table.insert(logHistory, logEntry)
    
    -- Manter apenas os últimos logs
    if #logHistory > maxHistory then
        table.remove(logHistory, 1)
    end
    
    -- Print para console
    local levelStr = ""
    if level == LOG_LEVELS.DEBUG then levelStr = "DEBUG"
    elseif level == LOG_LEVELS.INFO then levelStr = "INFO"
    elseif level == LOG_LEVELS.WARN then levelStr = "WARN"
    elseif level == LOG_LEVELS.ERROR then levelStr = "ERROR"
    end
    
    print("[" .. timestamp .. "] " .. levelStr .. ": " .. message)
    if data then
        print("  Data: " .. tostring(data))
    end
end

-- Funções de conveniência
function Logger:debug(message, data)
    self:log(LOG_LEVELS.DEBUG, message, data)
end

function Logger:info(message, data)
    self:log(LOG_LEVELS.INFO, message, data)
end

function Logger:warn(message, data)
    self:log(LOG_LEVELS.WARN, message, data)
end

function Logger:error(message, data)
    self:log(LOG_LEVELS.ERROR, message, data)
end

-- Obter histórico de logs
function Logger:getHistory()
    return logHistory
end

-- Limpar histórico
function Logger:clear()
    logHistory = {}
end

-- Salvar logs em arquivo
function Logger:saveToFile(filename)
    filename = filename or "game_log.txt"
    local file = io.open(filename, "w")
    if file then
        for _, entry in ipairs(logHistory) do
            local levelStr = ""
            if entry.level == LOG_LEVELS.DEBUG then levelStr = "DEBUG"
            elseif entry.level == LOG_LEVELS.INFO then levelStr = "INFO"
            elseif entry.level == LOG_LEVELS.WARN then levelStr = "WARN"
            elseif entry.level == LOG_LEVELS.ERROR then levelStr = "ERROR"
            end
            
            file:write(string.format("[%s] %s: %s\n", entry.timestamp, levelStr, entry.message))
            if entry.data then
                file:write("  Data: " .. tostring(entry.data) .. "\n")
            end
        end
        file:close()
        print("✅ Logs salvos em: " .. filename)
        return true
    else
        print("❌ Erro ao salvar logs em: " .. filename)
        return false
    end
end

return Logger 