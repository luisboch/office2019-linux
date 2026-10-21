#!/bin/bash
# Prepara o prefixo Proton: cabextract, symlinks -> copias, dependencias do winetricks, WebView2.
# E o installCommand do workspace Lock-In; roda dentro do sandbox (precisa de rede).
set -e
# cabextract (exigido pelo winetricks) nao existe no runtime Flatpak: usa os .deb oficiais do Debian, com hash fixo
TOOLS="$HOME/.local/opt/cabextract"
if [ ! -x "$TOOLS/usr/bin/cabextract" ]; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/c.deb" https://deb.debian.org/debian/pool/main/c/cabextract/cabextract_1.11-2_amd64.deb
  curl -fsSL -o "$tmp/m.deb" https://deb.debian.org/debian/pool/main/libm/libmspack/libmspack0_0.11-1_amd64.deb
  (cd "$tmp" && sha256sum -c - <<'EOF'
f66dfa011a39a82c1c601b308ef031ef65b29c856cd13a3d3eb194b947c5326d  c.deb
6695d3b9cc51a874feec328b40df0a59a2849c3fcc8cff77aa5f8d9f8e43fdca  m.deb
EOF
  )
  mkdir -p "$TOOLS"
  for f in c.deb m.deb; do
    mkdir "$tmp/x" && (cd "$tmp/x" && bsdtar -xf "../$f" && bsdtar -xf data.tar.* -C "$TOOLS")
    rm -rf "$tmp/x"
  done
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/cabextract" <<EOF
#!/bin/sh
LD_LIBRARY_PATH="$TOOLS/usr/lib/x86_64-linux-gnu" exec "$TOOLS/usr/bin/cabextract" "\$@"
EOF
chmod +x "$HOME/.local/bin/cabextract"
export PATH="$HOME/.local/bin:$PATH"

proton run wineboot -u
# O Proton cria os DLLs do prefixo como symlinks para o seu diretorio, somente leitura no sandbox:
# instaladores que substituem DLLs de sistema falham. Troca os symlinks por copias reais.
find "$WINEPREFIX/drive_c" -type l -lname "$PROTON_DIR/*" -print0 | while IFS= read -r -d '' l; do
  cp --remove-destination "$(readlink -f "$l")" "$l" && chmod u+w "$l"
done

# O wineserver as vezes fecha no momento em que o winetricks abre o proximo processo
# ("recvmsg: Connection reset by peer") e o winetricks aborta. Ele so marca um pacote como
# instalado quando termina, entao repetir refaz apenas o que faltou.
wt() {
  for i in 1 2 3; do
    winetricks -q "$@" && return 0
    echo "winetricks $* falhou (tentativa $i de 3)."
    "$PROTON_DIR/files/bin/wineserver" -k 2>/dev/null || true
    sleep 5
  done
  return 1
}
wt corefonts msxml6 riched20 gdiplus
# WebView2: renderiza a tela de login da conta Microsoft
wt webview2
wt win10
rm -rf "$HOME/.cache/winetricks"
echo "Prefixo pronto."
