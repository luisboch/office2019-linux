#!/bin/bash
# Instalacao completa, sem intervencao: prefixo, shims, Office (ODT) e pos-instalacao.
# E o comando de instalacao do workspace modelo do Lock-In; roda dentro do sandbox (precisa de rede,
# ~3,5 GB de download e algo como 20-40 min). Termina com o Wine parado e o Office pronto para o login.
set -e
R="$(cd "$(dirname "$0")" && pwd)"
# O comando de instalacao nao carrega o ~/.bashrc: sem isto o Xalia roda durante a instalacao.
export PROTON_USE_XALIA=0
bash "$R/setup-prefix.sh"
bash "$R/install-shims.sh"
bash "$R/install-office.sh"
bash "$R/postinstall.sh"
"$PROTON_DIR/files/bin/wineserver" -k 2>/dev/null || true
# Os pacotes baixados pela ODT so servem para instalar: libera ~3,5 GB.
rm -rf "$HOME/odt/Office"
echo "Office instalado. Abra o Word e clique em Entrar com a conta onde o Office 2019 esta registrado."
