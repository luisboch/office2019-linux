#!/bin/bash
# Baixa e instala o Office pela Office Deployment Tool (ODT) oficial, conforme configuration.xml.
# Roda dentro do sandbox, depois de setup-prefix.sh e install-shims.sh.
# O setup.exe /configure nao retorna sozinho: os servicos do Click-to-Run continuam rodando e a janela
# "Tudo pronto!" fica aberta. O script espera a instalacao terminar (WINWORD.EXE e a versao gravada no
# registro) e encerra o Wine.
set -e
R="$(cd "$(dirname "$0")" && pwd)"
ODT="$HOME/odt"
WS="$PROTON_DIR/files/bin/wineserver"
WORD="$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE"
mkdir -p "$ODT/logs" && cd "$ODT"
cp "$R/configuration.xml" .
[ -s setup.exe ] || curl -fsSL --retry 3 -o setup.exe https://officecdn.microsoft.com/pr/wsus/setup.exe
# C:\odt dentro do prefixo (SourcePath e Logging do configuration.xml)
ln -sfn "$ODT" "$WINEPREFIX/drive_c/odt"

installed() {
  [ -f "$WORD" ] && "${WINE:-wine}" reg query 'HKLM\Software\Microsoft\Office\ClickToRun\Configuration' \
    /v VersionToReport 2>/dev/null | grep -q 'VersionToReport'
}

if installed; then echo "Office ja instalado."; exit 0; fi

echo "Baixando o Office (~3,5 GB)..."
proton run ./setup.exe /download 'C:\odt\configuration.xml' || true
timeout 600 "$WS" -w || true
ls "$ODT/Office/Data" >/dev/null

echo "Instalando..."
proton run ./setup.exe /configure 'C:\odt\configuration.xml' &
setup=$!
for _ in $(seq 360); do               # ate 3 h, verificando a cada 30 s
  kill -0 "$setup" 2>/dev/null || break
  if installed; then sleep 60; break; fi  # folga para o Click-to-Run terminar de gravar
  sleep 30
done
"$WS" -k 2>/dev/null || true
wait "$setup" 2>/dev/null || true
installed || { echo "[ERROR] O Office nao foi instalado (veja $ODT/logs)."; exit 1; }
echo "Office instalado."
