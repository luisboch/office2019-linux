#!/bin/bash
# Instala os shims (dll/), a fonte Selawik (fonts/) e os ajustes de registro (office.reg) no prefixo.
# Roda dentro do sandbox (precisa de $WINEPREFIX, $PROTON_DIR e do comando proton).
# Seguro de repetir; rode de novo se trocar a versao do GE-Proton (ole32_wine.dll vem dele).
set -e
R="$(cd "$(dirname "$0")" && pwd)"
S32="$WINEPREFIX/drive_c/windows/system32"
put() { rm -f "$S32/$2"; cp -f "$1" "$S32/$2"; chmod 644 "$S32/$2"; }
put "$PROTON_DIR/files/lib/wine/x86_64-windows/ole32.dll" ole32_wine.dll
put "$R/dll/ole32.dll"    ole32.dll
put "$R/dll/ole32.dll"    ms365shim.dll
put "$R/dll/sppc.dll"     sppc.dll
put "$R/dll/ms365uia.dll" ms365uia.dll
put "$R/dll/d2d1.dll"     d2d1.dll
for f in "$R"/fonts/*.ttf; do cp -f "$f" "$WINEPREFIX/drive_c/windows/Fonts/"; done
cp "$R/office.reg" /tmp/office.reg
proton run regedit /S 'Z:\tmp\office.reg' >/dev/null 2>&1
# Xalia (ligado por padrao no GE-Proton) inunda o Office de chamadas COM e derruba o Excel no X11.
# O Lock-In carrega o ~/.bashrc do workspace antes de cada lancador e atalho.
grep -qx 'export PROTON_USE_XALIA=0' "$HOME/.bashrc" 2>/dev/null || echo 'export PROTON_USE_XALIA=0' >> "$HOME/.bashrc"
# Camada Vulkan implicita (o loader procura em ~/.local/share/vulkan): sem ela as janelas filhas
# do Office (grade, barra de formulas, status) mostram sempre o quadro anterior.
L="$HOME/.local/share/vulkan/implicit_layer.d"
mkdir -p "$L"
cp -f "$R/vulkan/VkLayer_WINE_present_sync.json" "$R/vulkan/libVkLayer_WINE_present_sync.so" "$L/"
echo "Shims instalados."
