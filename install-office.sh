#!/bin/bash
# Baixa e instala o Office pela Office Deployment Tool (ODT) oficial, conforme configuration.xml.
# Roda dentro do sandbox, depois de setup-prefix.sh e install-shims.sh.
# O setup.exe deixa servicos do Click-to-Run rodando: quando a janela mostrar "Tudo pronto!",
# feche-a; se o comando nao retornar, encerre os processos do Wine (pkill -9 -f 'wineserver|\.exe').
set -e
R="$(cd "$(dirname "$0")" && pwd)"
ODT="$HOME/odt"
mkdir -p "$ODT/logs" && cd "$ODT"
cp "$R/configuration.xml" .
[ -s setup.exe ] || curl -fsSL --retry 3 -o setup.exe https://officecdn.microsoft.com/pr/wsus/setup.exe
# C:\odt dentro do prefixo (SourcePath e Logging do configuration.xml)
ln -sfn "$ODT" "$WINEPREFIX/drive_c/odt"

echo "Baixando o Office (~3,5 GB)..."
proton run ./setup.exe /download 'C:\odt\configuration.xml' || true
"$PROTON_DIR/files/bin/wineserver" -w || true
ls "$ODT/Office/Data"

echo "Instalando..."
proton run ./setup.exe /configure 'C:\odt\configuration.xml' || true
"$PROTON_DIR/files/bin/wineserver" -w || true
ls "$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"
