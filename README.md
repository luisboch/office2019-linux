# Office 2019 on Linux (GE-Proton)

**English** | [Português (Brasil)](README.pt-BR.md)

A recipe to run **Microsoft Office Home & Student 2019** (retail licence tied to a Microsoft
account) on Linux with **GE-Proton11-7**, isolated in a (bubblewrap) sandbox. Tested in October 2026
on Ubuntu 26.04 (GNOME Wayland, Intel Iris Xe): 64-bit Word, Excel, PowerPoint and OneNote,
**activated by signing in to the Microsoft account, without typing a product key**.

Based on [Tombert/office365_flake](https://github.com/Tombert/office365_flake) (commit in
`src/UPSTREAM_COMMIT`), adapted from Nix to plain shell scripts.

> **This recipe does not contain Office.** Office is downloaded from Microsoft with the official
> Office Deployment Tool and requires your own valid licence. Do not share prefixes/backups with
> Office installed: Microsoft's licence terms do not allow redistributing the software.

## How it works

- Wine does not implement Windows' activation platform (SPP), so **entering the product key does
  not work**. Office is switched to token-based licensing ("vNext", `LicensingNext=2`) and is
  licensed by **signing in to the Microsoft account** the Office 2019 purchase is registered to.
- Native shims fill the gaps in GE-Proton 11's Wine 11.0:
  - `sppc.dll`: accepts licence installation (without it the installer aborts, error 30015-11 / 17002).
  - `ole32.dll` / `ms365shim.dll`: exports `CoRegisterActivationFilter`, fixes kernel32 stubs,
    WinRT, winhttp/wininet (sign-in), Direct2D/SVG (sign-in dialog).
  - `ms365uia.dll`: `CUIAutomationRegistrar` (crash when a document gets focus) and `InkDisp` (OneNote).
  - `d2d1.dll` from Wine 11.16: without it the ribbon controls render as grey blocks.
- A Vulkan layer (`VK_LAYER_WINE_present_sync`) fixes Office windows that always show the previous
  frame (item 10 below).
- The Segoe UI font is replaced by Selawik (Microsoft's open-source substitute).
- Sign-in uses WebView2 (`winetricks webview2`), not the Web Account Manager.

## Requirements

- GE-Proton11-7 (the binaries in `dll/` were built for it).
- The scripts that run "in the sandbox" expect the environment [Lock-In](https://gitlab.com/luis.c.boch/lockin) sets up for a
  `windows_proton` workspace: `$WINEPREFIX` (the prefix), `$PROTON_DIR` (the GE-Proton directory),
  a `proton` command on `PATH` (equivalent to `"$PROTON_DIR/proton"` with `STEAM_COMPAT_*` pointing
  at the prefix), `winetricks`, network and X/GPU access. With another sandbox, or none, set those
  variables and provide an equivalent `proton` command.
- Wine runs through Xwayland (X11 driver).
- To rebuild the shims (optional): [mise](https://mise.jdx.dev) (zig 0.15.2 and python 3.13).

## Lessons learned (read first)

1. **Use 64-bit.** The `Setup.exe` from the `.img` image installs 32-bit and fails at licensing (the
   shims are x64 only). Use the ODT with `OfficeClientEdition="64"`.
2. **Pin build `16.0.20326.20144`.** Office 2019 stopped at build 16.0.19127 (end of support in
   Oct 2025), and that build makes Word die on start (stack overflow in `AppVIsvSubsystems64.dll`
   during an HTTPS connection). The ODT accepts installing `HomeStudent2019Retail` at build 20326,
   the one Tombert validated. See `configuration.xml`.
3. **Word needs `/q`** (no splash screen): the splash thread brings the process down.
4. **Post-install is required** (`postinstall.sh`): mirror Office's `root/vfs` tree with symlinks
   and copy `AppvIsvSubsystems64.dll`/`C2R64.dll` into `Office16`.
5. WebView2 dialogs can stay **black for a few seconds** before painting. Wait.
6. **Excel: "IOPL not enabled"** on start is Windows error 197: Excel did not find `XLLEX.DLL` in
   the language folder (`Office16\1046`). It locates that folder through the qualified MSI component
   `{6679FC01-…}`, which `tools/msi-components.py` must point at a file in `Office16\<LCID>` (the
   script's `ROLE` table). On an older install, run `postinstall.sh` again.
7. **Xalia off** (`PROTON_USE_XALIA=0`): Proton's accessibility helper floods Office with COM calls
   and crashes Excel on X11. `install-shims.sh` writes the variable to the sandbox's `~/.bashrc`
   (Lock-In sources it before every launcher; elsewhere, export it before calling `proton`).
8. **OneNote: "You need to install the Desktop Experience"**: OneNote creates the Tablet PC ink
   object (`CLSID_InkDisp`), a stub in Wine, and concludes it is on Windows Server. `office.reg`
   registers the empty `InkDisp` from `ms365uia.dll` and the `Windows.Web.Http` stand-ins from
   `ms365shim.dll` (OneNote's UI creates an `HttpClient` on start).
9. `setup.exe /configure` never returns on its own: the Click-to-Run services keep running and the
   "You're all set!" window stays open. `install-office.sh` waits for `WINWORD.EXE` and the version
   written to the registry (`ClickToRun\Configuration\VersionToReport`), then stops Wine.
10. **Excel always shows the previous frame** (Delete does not clear the cells until the selection
    moves, the formula bar shows the previous cell's value, the start screen's hover highlight
    trails the mouse). Office's child windows draw with Direct3D (DXVK → Vulkan), and Wine renders
    Vulkan in child windows *offscreen*: right after `vkQueuePresentKHR` it copies the hidden X
    window into the visible one. On Xwayland, Mesa only queues the image and presents it later from
    its own thread, so the copy grabs the previous frame. The `VK_LAYER_WINE_present_sync` layer
    (`src/present_sync.c`) makes `vkQueuePresentKHR` wait for the present to finish
    (`vkWaitForPresentKHR`, with the id DXVK already sends). `install-shims.sh` installs it in
    `~/.local/share/vulkan/implicit_layer.d`; to turn it off, set `DISABLE_WINE_PRESENT_SYNC=1`.
    Things that do not help: disabling Office's hardware acceleration (blank window),
    `PROTON_USE_WINED3D=1` (no text), DXVK/Mesa present modes, a Wine virtual desktop.
    Reported as [ValveSoftware/Proton#10284](https://github.com/ValveSoftware/Proton/issues/10284).

## Step by step

**Quickest way, with [Lock-In](https://gitlab.com/luis.c.boch/lockin):** download
`office-2019.model.zip` from the [latest release](https://github.com/luisboch/office2019-linux/releases/latest)
and import it in Lock-In. The template holds only this recipe and the workspace's settings (no
Wine prefix, nothing from Microsoft); importing it creates the workspace and runs `install-all.sh`
by itself. Wait for it to finish (20-40 min, ~3.5 GB download) and go to step 6.

The steps below build the same workspace by hand and end in exactly the same result: the template
only saves the clicks of creating the workspace, copying the recipe and filling in its settings.

1. **Shims** (host; optional, `dll/` and `vulkan/` ship prebuilt for GE-Proton11-7):
   ```bash
   ./build-shims.sh ~/path/to/GE-Proton11-7
   ```
2. **Sandbox/workspace** of type `windows_proton`, GE-Proton11-7, with network, X/GPU and audio.
   Copy this folder into the workspace's home (in Lock-In: the workspace files →
   `~/office2019-linux`) and share the host's Documents folder as the prefix's
   `drive_c/users/steamuser/Documents` (Office saves there by default). Install command:
   `bash "$HOME/office2019-linux/install-all.sh"`.
3. **Language:** `configuration.xml` installs Portuguese (`pt-br`). For another language, change
   `Language ID` (e.g. `en-us`).
4. Inside the sandbox, from this folder, everything in one go (this is what the workspace's install
   command can run):
   ```bash
   bash install-all.sh
   ```
   It runs `setup-prefix.sh`, `install-shims.sh`, `install-office.sh` and `postinstall.sh` in
   order, unattended, and deletes the packages the ODT downloaded at the end. The steps can also be
   run one by one.
5. **Launchers** (run with `proton run`):
   - Word: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/WINWORD.EXE" /q`
   - Excel: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/EXCEL.EXE"`
   - PowerPoint: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/POWERPNT.EXE"`
   - OneNote: `"$WINEPREFIX/drive_c/Program Files/Microsoft Office/root/Office16/ONENOTE.EXE"`
6. **Activation:** open Word, click the blue **Sign in** button (it may show no text before `d2d1`
   is in place) and sign in with the account Office 2019 is registered to. Do **not** use "I have
   a product key". If Office shows Microsoft's licence terms, accept them. Check
   **File → Account**: "Microsoft Office Home and Student 2019".

## Maintenance

- **Updates** are disabled (`<Updates Enabled="FALSE"/>`): Click-to-Run's background updater is
  unreliable on Wine. To change build, edit `Version` in `configuration.xml` and run
  `install-office.sh` + `postinstall.sh` again.
- **Switched GE-Proton version?** `dll/ole32.dll` is generated from its `ole32.dll`: run
  `build-shims.sh` again, then `install-shims.sh`.
- **"Do you want to start in safe mode?"** after a crash: delete
  `HKCU\Software\Microsoft\Office\16.0\Word\Resiliency` (or `Excel`, `PowerPoint`).
- **"Something went wrong" (0x5)** on start after a crash: the file
  `drive_c/ProgramData/Microsoft/Office/ClickToRunPackageLocker` lost its permissions;
  `chmod u+rwx,g+rwx` it.

## Item 10 diagnosis (for whoever fixes it in Wine)

Analysed with GE-Proton11-7 (ValveSoftware/wine `46b2910`), DXVK v3.1-19, Flatpak runtime
Freedesktop 25.08 (Vulkan loader 1.4.321, Mesa 26.2), Mesa ANV, Xwayland. The same code is in
Valve's `proton_11.0` and in Wine master (11.20).

- **Code path:** `needs_offscreen_rendering()` (`dlls/winex11.drv/init.c`) returns TRUE for a child
  window that needs compositing; `win32u_vkQueuePresentKHR` (`dlls/win32u/vulkan.c`) calls the host
  `vkQueuePresentKHR` and right after it `client_surface_present()` →
  `X11DRV_client_surface_present`, which `NtGdiStretchBlt`s the redirected (XComposite) X window
  into the toplevel without waiting for the present to complete.
- **Confirm the issue:** `WINEDEBUG=-all,trace+x11drv` shows Excel's client surfaces with
  `offscreen 1`.
- **Confirm the layer is loaded:** `grep present_sync /proc/$(pgrep -f EXCEL.EXE)/maps`.
- **Limitation:** the layer only acts when the app enables `VK_KHR_present_wait` and chains
  `VkPresentIdKHR` (DXVK does). A fix in Wine would have to wait inside `win32u` before
  `client_surface_present()`. Report text in `upstream/proton-issue.md`.

## Files

| File | Runs on | What it does |
|---|---|---|
| `build-shims.sh` | host | builds `dll/` and `vulkan/` from `src/` (zig + python via mise), downloads Wine 11.16's `d2d1` and Selawik |
| `setup-prefix.sh` | sandbox | Proton prefix + `corefonts msxml6 riched20 gdiplus webview2 win10` |
| `install-shims.sh` | sandbox | copies the shims to `system32`, installs fonts and the Vulkan layer, applies `office.reg`, turns Xalia off |
| `configuration.xml` | — | ODT configuration (Home & Student 2019, 64-bit, build 20326, pt-BR) |
| `install-all.sh` | sandbox | unattended full install (the four scripts below, in order) |
| `install-office.sh` | sandbox | downloads the official ODT, runs `/download` + `/configure` and stops Wine when done |
| `postinstall.sh` | sandbox | mirrors the VFS, registers MSI components and FM20, reapplies the registry |
| `office.reg` | — | DLL overrides, sign-in without WAM, `LicensingNext`, OneNote, default folders |
| `dll/`, `fonts/`, `vulkan/` | — | prebuilt binaries (for GE-Proton11-7) |
| `src/`, `tools/` | — | sources of the shims, the Vulkan layer (`src/present_sync.c`) and the MSI component generator |
| `upstream/` | — | the item 10 report sent to Proton |

Script comments are in Portuguese.

## Licences

- Shims in `src/`/`dll/` and `tools/msi-components.py`: from Tombert/office365_flake, LGPL-2.1
  (`LICENSE`).
- Vulkan layer (`src/present_sync.c`, `vulkan/`): new code from this recipe, no copyright claimed,
  under the same terms as Wine (LGPL-2.1 or later).
- `dll/d2d1.dll`: Wine 11.16 (LGPL-2.1), binary from
  [Kron4ek/Wine-Builds](https://github.com/Kron4ek/Wine-Builds/releases/tag/11.16); source at
  [gitlab.winehq.org/wine/wine](https://gitlab.winehq.org/wine/wine/-/tree/wine-11.16).
- Selawik fonts (`fonts/`): Microsoft, SIL Open Font License 1.1 (`fonts/LICENSE.txt`).
- Microsoft Office, WebView2 and the `corefonts` fonts are **not** part of this recipe: they are
  downloaded from Microsoft during installation, under Microsoft's terms.
