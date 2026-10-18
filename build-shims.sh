#!/bin/bash
# Compila os shims (dll/) a partir de src/, com zig e python gerenciados pelo mise.
# Roda no host. Uso: ./build-shims.sh <diretorio do GE-Proton11-7>
#   ex.: ./build-shims.sh ~/.config/lockin/runtimes/proton/GE-Proton11-7
# O ole32.dll e gerado a partir do ole32 do Proton informado: recompile ao trocar de GE-Proton.
set -e
R="$(cd "$(dirname "$0")" && pwd)"
PROTON="${1:?informe o diretorio do GE-Proton}"
B="$(mktemp -d)"; trap 'rm -rf "$B"' EXIT
export ZIG_GLOBAL_CACHE_DIR="$B/zig-cache" ZIG_LOCAL_CACHE_DIR="$B/zig-local"
zigcc() { mise exec zig@0.15.2 -- zig cc -target x86_64-windows-gnu -shared -O2 "$@"; }

zigcc -o "$R/dll/sppc.dll" "$R/src/sppc.c"
zigcc -o "$R/dll/ms365uia.dll" "$R/src/uia.c" -lole32 -luuid
mise exec python@3.13 -- python -m venv "$B/venv"
"$B/venv/bin/pip" -q install pefile
"$B/venv/bin/python" -I "$R/src/gen-def.py" "$PROTON/files/lib/wine/x86_64-windows/ole32.dll" "$B/ole32.def"
zigcc -o "$R/dll/ole32.dll" "$R/src/shim.c" "$B/ole32.def"

# d2d1 do Wine 11.16 (corrige o fill mode de geometry groups), com a assinatura de builtin apagada
# para que o Proton o carregue como DLL nativo.
curl -fsSL -o "$B/w.tar.xz" https://github.com/Kron4ek/Wine-Builds/releases/download/11.16/wine-11.16-amd64.tar.xz
tar -xJf "$B/w.tar.xz" -C "$B" --wildcards '*/lib/wine/x86_64-windows/d2d1.dll'
cp "$(find "$B" -name d2d1.dll | head -1)" "$R/dll/d2d1.dll"; chmod u+w "$R/dll/d2d1.dll"
[ "$(dd if="$R/dll/d2d1.dll" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ]
printf 'ms365 native DLL' | dd of="$R/dll/d2d1.dll" bs=1 seek=64 count=16 conv=notrunc 2>/dev/null

# Camada Vulkan que espera cada present terminar antes de o Wine copiar as janelas filhas
# (sem ela o Excel mostra sempre o quadro anterior). Biblioteca Linux, roda no runtime Flatpak.
curl -fsSL -o "$B/vkh.tar.gz" https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v1.4.321.tar.gz
tar -xzf "$B/vkh.tar.gz" -C "$B"
mise exec zig@0.15.2 -- zig cc -target x86_64-linux-gnu.2.28 -shared -fPIC -O2 -fvisibility=hidden \
    -I "$B/Vulkan-Headers-1.4.321/include" -o "$R/vulkan/libVkLayer_WINE_present_sync.so" "$R/src/present_sync.c" -lpthread

# Selawik: substituta open-source (SIL OFL 1.1) da Segoe UI, publicada pela Microsoft
mkdir -p "$R/fonts"
curl -fsSL -o "$B/s.zip" https://github.com/microsoft/Selawik/releases/download/1.01/Selawik_Release.zip
python3 -I -c 'import zipfile,sys;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$B/s.zip" "$B/selawik"
find "$B/selawik" -name '*.ttf' -exec cp {} "$R/fonts/" \;
curl -fsSL -o "$R/fonts/LICENSE.txt" https://raw.githubusercontent.com/microsoft/Selawik/1.01/LICENSE.txt
ls -la "$R/dll" "$R/fonts" "$R/vulkan"
