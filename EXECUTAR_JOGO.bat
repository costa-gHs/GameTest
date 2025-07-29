@echo off
title SLIME: Tempest Trials - Inicializador
echo.
echo ==========================================
echo    SLIME: TEMPEST TRIALS
echo    "Devore, Analise, Evolua"
echo ==========================================
echo.
echo Verificando Love2D...

:: Tentar encontrar Love2D em locais comuns
set LOVE_PATH=""

:: Verificar pasta atual
if exist "love.exe" (
    set LOVE_PATH="love.exe"
    goto :found
)

:: Verificar Program Files
if exist "C:\Program Files\LOVE\love.exe" (
    set LOVE_PATH="C:\Program Files\LOVE\love.exe"
    goto :found
)

:: Verificar Program Files (x86)
if exist "C:\Program Files (x86)\LOVE\love.exe" (
    set LOVE_PATH="C:\Program Files (x86)\LOVE\love.exe"
    goto :found
)

:: Verificar PATH do sistema
love --version >nul 2>&1
if %errorlevel% == 0 (
    set LOVE_PATH="love"
    goto :found
)

:: Não encontrou Love2D
echo ERRO: Love2D nao encontrado!
echo.
echo Por favor:
echo 1. Baixe Love2D 11.x em: https://love2d.org/
echo 2. Instale ou extraia na pasta do jogo
echo 3. Execute este script novamente
echo.
pause
exit /b 1

:found
echo Love2D encontrado: %LOVE_PATH%
echo.
echo Iniciando SLIME: Tempest Trials...
echo.
echo Controles basicos:
echo   WASD = Movimento
echo   Shift+WASD = Dash viscoso
echo   Espaco/Click = Predacao
echo   X/Click direito = Ataque
echo   C = Agarre
echo   A = Analise
echo   Q = Ativar forma
echo   T = Habilidade unica
echo   Esc = Sair
echo.

:: Executar o jogo
%LOVE_PATH% .

:: Se chegou aqui, o jogo foi fechado
echo.
echo Jogo finalizado. Obrigado por jogar!
echo.
pause 