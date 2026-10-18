#!/bin/bash
# Ajustes pos-instalacao do Office (C2R 64 bits) no prefixo Proton.
# Adaptado de post_install_fixups em https://github.com/Tombert/office365_flake (ms365.sh).
# Roda dentro do sandbox (precisa de $WINEPREFIX e do comando proton).
set -e
R="$(cd "$(dirname "$0")" && pwd)"
C="$WINEPREFIX/drive_c"
ROOT="$C/Program Files/Microsoft Office/root"
C2R="$C/Program Files/Common Files/Microsoft Shared/ClickToRun"

# 1. Office guarda seus DLLs em root/vfs e depende do App-V para redirecionar os caminhos reais.
#    No Wine isso falha: espelha a arvore com symlinks (so onde ainda nao existe nada).
link_tree() {
  local src="$1" dst="$2" e name
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  for e in "$src"/*; do
    [ -e "$e" ] || continue
    name="${e##*/}"
    if [ ! -e "$dst/$name" ]; then
      ln -s "$e" "$dst/$name"
    elif [ -d "$e" ] && [ -d "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      link_tree "$e" "$dst/$name"
    fi
  done
}
link_tree "$ROOT/vfs/ProgramFilesCommonX64" "$C/Program Files/Common Files"
link_tree "$ROOT/vfs/ProgramFilesCommonX86" "$C/Program Files (x86)/Common Files"
link_tree "$ROOT/vfs/ProgramFilesX64"       "$C/Program Files"
link_tree "$ROOT/vfs/ProgramFilesX86"       "$C/Program Files (x86)"
link_tree "$ROOT/vfs/Fonts"                 "$C/windows/Fonts"

# 2. Os DLLs do subsistema App-V precisam ficar ao lado dos executaveis do Office.
for f in AppvIsvSubsystems64.dll C2R64.dll; do
  [ -f "$C2R/$f" ] && [ ! -f "$ROOT/Office16/$f" ] && cp -f "$C2R/$f" "$ROOT/Office16/$f"
done

# 3. Registra os componentes MSI (corretor ortografico, conversores) que o integrador nao gravou.
if command -v python3 >/dev/null; then
  python3 -I "$R/tools/msi-components.py" "$C" /tmp/msi-components.reg && \
    proton run regedit /S 'Z:\tmp\msi-components.reg' >/dev/null 2>&1 || true
fi

# 4. MSForms (UserForms do VBA).
[ -f "$ROOT/vfs/System/FM20.DLL" ] && \
  proton run regsvr32 /s 'C:\Program Files\Microsoft Office\root\vfs\System\FM20.DLL' >/dev/null 2>&1 || true

# 5. Reaplica os ajustes de registro (o instalador pode ter sobrescrito algum).
cp "$R/office.reg" /tmp/office.reg
proton run regedit /S 'Z:\tmp\office.reg' >/dev/null 2>&1
echo "Pos-instalacao concluida."
