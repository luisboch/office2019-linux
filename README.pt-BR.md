# Office 2019 no Linux (GE-Proton)

[English](README.md) | **Português (Brasil)**

Receita para rodar o **Microsoft Office Home & Student 2019** (licença de varejo vinculada à conta
Microsoft) no Linux com **GE-Proton11-7**, isolado num sandbox (bubblewrap). Testada em 2026-10 no
Ubuntu 26.04 (GNOME Wayland, Intel Iris Xe): Word, Excel, PowerPoint e OneNote 64 bits,
**ativados pelo login na conta Microsoft, sem digitar chave**.

Baseada no trabalho de [Tombert/office365_flake](https://github.com/Tombert/office365_flake)
(commit em `src/UPSTREAM_COMMIT`), adaptada do Nix para scripts simples.

> **Esta receita não contém o Office.** O Office é baixado da Microsoft pela Office Deployment Tool
> oficial e exige uma licença válida sua. Não compartilhe prefixos/backups com o Office instalado:
> a licença da Microsoft não permite redistribuir o software.

## Como funciona

- O Wine não implementa a plataforma de ativação do Windows (SPP), então **digitar a chave não
  funciona**. O Office é posto no licenciamento por token ("vNext", `LicensingNext=2`) e licenciado
  pelo **login na conta Microsoft** onde a compra do Office 2019 está registrada.
- Shims nativos tapam o que falta no Wine 11.0 do GE-Proton 11:
  - `sppc.dll`: aceita a instalação de licenças (sem ele o instalador aborta, erro 30015-11 / 17002).
  - `ole32.dll` / `ms365shim.dll`: exporta `CoRegisterActivationFilter`, corrige stubs do kernel32,
    WinRT, winhttp/wininet (login), Direct2D/SVG (diálogo de login).
  - `ms365uia.dll`: `CUIAutomationRegistrar` (crash ao focar um documento) e `InkDisp` (OneNote).
  - `d2d1.dll` do Wine 11.16: sem ele os controles da faixa de opções viram blocos cinza.
- Uma camada Vulkan (`VK_LAYER_WINE_present_sync`) corrige as janelas do Office que mostram sempre
  o quadro anterior (item 10 abaixo).
- A fonte Segoe UI é trocada pela Selawik (substituta open-source da Microsoft).
- O login usa o WebView2 (`winetricks webview2`), não o Web Account Manager.

## Requisitos

- GE-Proton11-7 (os binários de `dll/` foram gerados para ele).
- Os scripts que rodam "no sandbox" esperam o ambiente que o [Lock-In](https://gitlab.com/luis.c.boch/lockin) monta para um workspace
  `windows_proton`: `$WINEPREFIX` (prefixo), `$PROTON_DIR` (diretório do GE-Proton), o comando
  `proton` no `PATH` (equivale a `"$PROTON_DIR/proton"` com `STEAM_COMPAT_*` apontando para o
  prefixo), `winetricks`, rede e acesso ao X/GPU. Com outro sandbox ou sem sandbox, defina essas
  variáveis e um `proton` equivalente.
- O Wine roda pelo XWayland (driver X11).
- Para recompilar os shims (opcional): [mise](https://mise.jdx.dev) (zig 0.15.2 e python 3.13).

## Pontos que custaram caro (leia antes)

1. **Use 64 bits.** O `Setup.exe` da imagem `.img` instala 32 bits e falha no licenciamento (os
   shims são só x64). Use a ODT com `OfficeClientEdition="64"`.
2. **Fixe a build `16.0.20326.20144`.** O Office 2019 parou na build 16.0.19127 (fim do suporte em
   out/2025), e nela o Word morre ao abrir (estouro de pilha no `AppVIsvSubsystems64.dll` durante
   uma conexão HTTPS). A ODT aceita instalar o `HomeStudent2019Retail` na build 20326, que é a
   validada pelo Tombert. Ver `configuration.xml`.
3. **Word precisa de `/q`** (sem tela de abertura): a thread do splash derruba o processo.
4. **Pós-instalação obrigatória** (`postinstall.sh`): espelhar a árvore `root/vfs` do Office com
   symlinks e copiar `AppvIsvSubsystems64.dll`/`C2R64.dll` para `Office16`.
5. Os diálogos em WebView2 podem ficar **pretos alguns segundos** antes de desenhar. Espere.
6. **Excel: "IOPL not enabled"** ao abrir é o erro 197 do Windows: o Excel não achou o `XLLEX.DLL`
   da pasta de idioma (`Office16\1046`). Ele localiza essa pasta pelo componente MSI qualificado
   `{6679FC01-…}`, que o `tools/msi-components.py` precisa apontar para um arquivo de
   `Office16\<LCID>` (tabela `ROLE` do script). Numa instalação antiga, rode o `postinstall.sh` de
   novo.
7. **Xalia desligado** (`PROTON_USE_XALIA=0`): o auxiliar de acessibilidade do Proton inunda o
   Office com chamadas COM e derruba o Excel no X11. O `install-shims.sh` grava a variável no
   `~/.bashrc` do sandbox (o Lock-In o carrega antes de cada lançador; em outro ambiente, exporte-a
   antes de chamar o `proton`).
8. **OneNote: "É preciso instalar a Experiência Desktop"**: o OneNote cria o objeto de tinta do
   Tablet PC (`CLSID_InkDisp`), que é um stub no Wine, e conclui que está num Windows Server. O
   `office.reg` registra o `InkDisp` vazio do `ms365uia.dll` e os substitutos de `Windows.Web.Http`
   do `ms365shim.dll` (a interface do OneNote cria um `HttpClient` ao abrir).
9. O `setup.exe /configure` não retorna sozinho: os serviços do Click-to-Run continuam rodando e a
   janela "Tudo pronto!" fica aberta. O `install-office.sh` espera o `WINWORD.EXE` e a versão
   gravada no registro (`ClickToRun\Configuration\VersionToReport`) e encerra o Wine.
10. **Excel mostra sempre o quadro anterior** (Delete não limpa as células até mudar a seleção, a
    barra de fórmulas mostra o valor da célula anterior, o destaque da tela inicial fica atrás do
    mouse). As janelas filhas do Office desenham com Direct3D (DXVK → Vulkan), e o Wine renderiza
    Vulkan de janelas filhas *offscreen*: logo depois do `vkQueuePresentKHR` ele copia a janela X
    escondida para a janela visível. No XWayland, o Mesa só enfileira a imagem e apresenta depois,
    numa thread própria, então a cópia pega o quadro anterior. A camada
    `VK_LAYER_WINE_present_sync` (`src/present_sync.c`) faz o `vkQueuePresentKHR` esperar o present
    terminar (`vkWaitForPresentKHR`, com o id que o DXVK já envia). O `install-shims.sh` a instala
    em `~/.local/share/vulkan/implicit_layer.d`; para desligar, `DISABLE_WINE_PRESENT_SYNC=1`. Não
    adiantam: desligar a aceleração de hardware do Office (janela em branco),
    `PROTON_USE_WINED3D=1` (sem texto), modos de present do DXVK/Mesa nem desktop virtual do Wine.
    Relatado em [ValveSoftware/Proton#10284](https://github.com/ValveSoftware/Proton/issues/10284).

## Passo a passo

**Com um modelo do Lock-In:** um workspace do Lock-In com esta receita pode ser salvo como modelo
(`.model.zip`: a receita e as configurações do workspace, sem o prefixo do Wine e sem o Office).
Ao importá-lo, o Lock-In cria o workspace e roda o `install-all.sh` sozinho; espere terminar
(20-40 min) e vá para o passo 6. Os passos abaixo montam o mesmo workspace à mão.

1. **Shims** (host; opcional, `dll/` e `vulkan/` já vêm prontos para GE-Proton11-7):
   ```bash
   ./build-shims.sh ~/caminho/para/GE-Proton11-7
   ```
2. **Sandbox/workspace** do tipo `windows_proton`, GE-Proton11-7, com rede, X/GPU e áudio. Copie
   esta pasta para a home do workspace (no Lock-In: arquivos do workspace → `~/office2019-linux`)
   e compartilhe a pasta Documentos do host como `drive_c/users/steamuser/Documents` do prefixo (o
   Office salva ali por padrão). Comando de instalação: `bash "$HOME/office2019-linux/install-all.sh"`.
3. **Idioma:** o `configuration.xml` instala em português (`pt-br`). Para outro idioma, troque o
   `Language ID` (ex.: `en-us`).
4. Dentro do sandbox, a partir desta pasta, tudo de uma vez (é o que o comando de instalação do
   workspace pode rodar):
   ```bash
   bash install-all.sh
   ```
   Ele roda `setup-prefix.sh`, `install-shims.sh`, `install-office.sh` e `postinstall.sh` em
   sequência, sem intervenção, e apaga os pacotes baixados pela ODT no fim. Os passos também podem
   ser rodados um a um.
5. **Lançadores** (rodados com `proton run`):
   - Word: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE" /q`
   - Excel: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/EXCEL.EXE"`
   - PowerPoint: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/POWERPNT.EXE"`
   - OneNote: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/ONENOTE.EXE"`
6. **Ativação:** abra o Word, clique no botão azul de **Entrar** (pode aparecer sem texto antes do
   `d2d1`), faça login com a conta onde o Office 2019 está registrado. **Não** use "Eu tenho uma
   chave de produto". Se o Office mostrar os termos de licença da Microsoft, aceite-os. Confira em
   **Arquivo → Conta**: "Microsoft Office Home and Student 2019".

## Manutenção

- **Atualizações** estão desligadas (`<Updates Enabled="FALSE"/>`): o atualizador em segundo plano
  do Click-to-Run é instável no Wine. Para mudar de build, ajuste `Version` no `configuration.xml`
  e rode `install-office.sh` + `postinstall.sh` de novo.
- **Trocou de versão do GE-Proton?** `dll/ole32.dll` é gerado a partir do `ole32.dll` dele: rode
  `build-shims.sh` de novo e depois `install-shims.sh`.
- **"Deseja iniciar no modo de segurança?"** depois de um crash: apague a chave
  `HKCU\Software\Microsoft\Office\16.0\Word\Resiliency` (ou `Excel`, `PowerPoint`).
- **"Algo deu errado" (0x5)** ao abrir depois de um crash: o arquivo
  `drive_c/ProgramData/Microsoft/Office/ClickToRunPackageLocker` ficou sem permissão;
  `chmod u+rwx,g+rwx` nele.

## Diagnóstico do item 10 (para quem for corrigir no Wine)

Analisado com GE-Proton11-7 (ValveSoftware/wine `46b2910`), DXVK v3.1-19, runtime Flatpak
Freedesktop 25.08 (loader Vulkan 1.4.321, Mesa 26.2), Mesa ANV, XWayland. O mesmo código está no
`proton_11.0` da Valve e no Wine master (11.20).

- **Caminho no Wine:** `needs_offscreen_rendering()` (`dlls/winex11.drv/init.c`) devolve TRUE para
  janela filha que precisa de composição; `win32u_vkQueuePresentKHR` (`dlls/win32u/vulkan.c`) chama
  o `vkQueuePresentKHR` do host e logo em seguida `client_surface_present()` →
  `X11DRV_client_surface_present`, que faz `NtGdiStretchBlt` da janela X redirecionada (XComposite)
  para a janela de topo, sem esperar o present terminar.
- **Confirmar o problema:** `WINEDEBUG=-all,trace+x11drv` mostra as superfícies criadas pelo Excel
  com `offscreen 1`.
- **Confirmar que a camada carregou:** `grep present_sync /proc/$(pgrep -f EXCEL.EXE)/maps`.
- **Limitação:** a camada só age quando o app liga `VK_KHR_present_wait` e manda `VkPresentIdKHR`
  (o DXVK faz isso). Uma correção no Wine precisaria esperar dentro do `win32u` antes do
  `client_surface_present()`. Texto do relato em `upstream/proton-issue.md`.

## Arquivos

| Arquivo | Onde roda | O que faz |
|---|---|---|
| `build-shims.sh` | host | compila `dll/` e `vulkan/` a partir de `src/` (zig + python via mise), baixa o `d2d1` do Wine 11.16 e a Selawik |
| `setup-prefix.sh` | sandbox | prefixo Proton + `corefonts msxml6 riched20 gdiplus webview2 win10` |
| `install-shims.sh` | sandbox | copia os shims para `system32`, instala fontes e a camada Vulkan, aplica `office.reg`, desliga o Xalia |
| `configuration.xml` | — | configuração da ODT (Home & Student 2019, 64 bits, build 20326, pt-BR) |
| `install-all.sh` | sandbox | instalação completa sem intervenção (os quatro scripts abaixo, em ordem) |
| `install-office.sh` | sandbox | baixa a ODT oficial, roda `/download` + `/configure` e encerra o Wine quando termina |
| `postinstall.sh` | sandbox | espelha o VFS, registra componentes MSI e FM20, reaplica o registro |
| `office.reg` | — | overrides de DLL, login sem WAM, `LicensingNext`, OneNote, pastas padrão |
| `dll/`, `fonts/`, `vulkan/` | — | binários prontos (para GE-Proton11-7) |
| `src/`, `tools/` | — | fontes dos shims, da camada Vulkan (`src/present_sync.c`) e o gerador de componentes MSI |
| `upstream/` | — | relato do item 10 enviado ao Proton |

## Licenças

- Shims em `src/`/`dll/` e `tools/msi-components.py`: de Tombert/office365_flake, LGPL-2.1
  (`LICENSE`).
- Camada Vulkan (`src/present_sync.c`, `vulkan/`): código novo desta receita, sem copyright
  reservado, sob os mesmos termos do Wine (LGPL-2.1 ou posterior).
- `dll/d2d1.dll`: Wine 11.16 (LGPL-2.1), binário de
  [Kron4ek/Wine-Builds](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.16); código-fonte em
  [gitlab.winehq.org/wine/wine](https://gitlab.winehq.org/wine/wine/-/tree/wine-11.16).
- Fontes Selawik (`fonts/`): Microsoft, SIL Open Font License 1.1 (`fonts/LICENSE.txt`).
- Microsoft Office, WebView2 e as fontes do `corefonts` **não** fazem parte desta receita: são
  baixados da Microsoft durante a instalação, sob os termos dela.
