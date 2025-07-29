#!/bin/bash

clear
echo "=========================================="
echo "    SLIME: TEMPEST TRIALS"
echo "    \"Devore, Analise, Evolua\""
echo "=========================================="
echo
echo "Verificando Love2D..."

# Tentar encontrar Love2D
LOVE_PATH=""

# Verificar se love está no PATH
if command -v love >/dev/null 2>&1; then
    LOVE_PATH="love"
elif command -v love2d >/dev/null 2>&1; then
    LOVE_PATH="love2d"
# Verificar locais comuns no macOS
elif [ -f "/Applications/love.app/Contents/MacOS/love" ]; then
    LOVE_PATH="/Applications/love.app/Contents/MacOS/love"
# Verificar pasta atual
elif [ -f "./love" ]; then
    LOVE_PATH="./love"
else
    echo "ERRO: Love2D não encontrado!"
    echo
    echo "Por favor:"
    echo "1. Instale Love2D 11.x:"
    echo "   - Ubuntu/Debian: sudo apt install love"
    echo "   - macOS: brew install love"
    echo "   - Ou baixe em: https://love2d.org/"
    echo "2. Execute este script novamente"
    echo
    read -p "Pressione Enter para sair..."
    exit 1
fi

echo "Love2D encontrado: $LOVE_PATH"
echo
echo "Iniciando SLIME: Tempest Trials..."
echo
echo "Controles básicos:"
echo "  WASD = Movimento"
echo "  Espaço = Predação"
echo "  A = Análise" 
echo "  Q = Ativar forma"
echo "  Esc = Sair"
echo

# Executar o jogo
$LOVE_PATH game_main.lua

# Se chegou aqui, o jogo foi fechado
echo
echo "Jogo finalizado. Obrigado por jogar!"
echo 