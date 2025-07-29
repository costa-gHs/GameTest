-- main.lua - Entry Point para SLIME: Tempest Trials
-- Este arquivo redireciona para o jogo principal ou gerador de sprites

-- Por padrão, executa o jogo principal (SLIME: Tempest Trials)
-- Para executar o gerador de sprites, use: love . --generator

-- Verificar argumentos
local runGenerator = false
if love.arg then
    for _, arg in ipairs(love.arg) do
        if arg == "--generator" or arg == "--sprites" then
            runGenerator = true
            break
        end
    end
end

if runGenerator then
    -- Carregar gerador de sprites original
    require("sprite_generator")
else
    -- Carregar jogo principal
    require("game_main")
end