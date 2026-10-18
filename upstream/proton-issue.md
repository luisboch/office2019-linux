[General issue] Offscreen Vulkan child windows always show the previous frame on Xwayland (win32u copies before the present completes) – Microsoft Excel 2019

## Summary

When a Vulkan swapchain belongs to a child window that Wine renders offscreen, the window always shows the **previous** frame. `win32u_vkQueuePresentKHR` calls the host `vkQueuePresentKHR` and immediately afterwards `client_surface_present()`, which on winex11 (`X11DRV_client_surface_present`) copies the XComposite-redirected client window into the toplevel with `NtGdiStretchBlt`. Mesa's X11 WSI on Xwayland only queues the image at that point and presents it later from its own thread (after the fence), so the copy grabs what was there before. Nothing on screen is updated until the next present, which in a desktop app usually means the next user input.

The code is the same in `ValveSoftware/wine` `proton_11.0` (e60892cc23) and in upstream wine master (wine-11.20), `dlls/win32u/vulkan.c`:

```c
    res = device->p_vkQueuePresentKHR( queue->host.queue, present_info );

    for (uint32_t i = 0; i < present_info->swapchainCount; i++)
    {
        ...
        client_surface_present( surface->client );
```

## Environment

- App: Microsoft Office Home & Student 2019 (Excel 64-bit, build 16.0.20326.20144), not a Steam title
- Proton: GE-Proton11-7 (ValveSoftware/wine 46b2910, DXVK v3.1-19). Not tested with Valve Proton 11, but the code path above is identical there.
- Runs inside a bubblewrap sandbox on the Flatpak runtime org.freedesktop.Platform 25.08 (Vulkan loader 1.4.321, Mesa 26.2.4)
- Distro/kernel: Ubuntu 26.04.1, Linux 7.0.0
- Desktop: GNOME Wayland, app runs under Xwayland (winex11)
- GPU: Intel Iris Xe (Alder Lake-UP3, 8086:46a8), Mesa ANV

## Symptoms / reproduction

1. Open Excel, type something in a few cells.
2. Select the cells and press Delete: the cells stay on screen. They disappear only after the selection moves.
3. Same for the formula bar (shows the previous cell's value), the status bar and the hover highlight on the start screen, which trails one step behind the mouse.

Office draws the grid, formula bar and status bar as child windows with Direct3D 11 (DXVK). `WINEDEBUG=-all,trace+x11drv` shows Excel creating 4 client surfaces, all with `offscreen 1` (`needs_offscreen_rendering()` in `dlls/winex11.drv/init.c`, child window that needs compositing).

Things that do not help: `MESA_VK_WSI_PRESENT_MODE=fifo`, `vk_xwayland_wait_ready=false`, `dxvk.tearFree = False`, a Wine virtual desktop, Office's `DisableHardwareAcceleration` (blank window), `PROTON_USE_WINED3D=1` (no text).

## Workaround / confirmation

A small implicit Vulkan layer that waits for the present to finish before returning from `vkQueuePresentKHR` fixes it completely. Every update shows up immediately. DXVK already enables `VK_KHR_present_id` + `VK_KHR_present_wait` and chains `VkPresentIdKHR`, so the layer only does:

```c
res = next_present( queue, info );
if (res >= 0 && present_wait && (id = find_struct( info->pNext, VK_STRUCTURE_TYPE_PRESENT_ID_KHR )))
    for (i = 0; i < info->swapchainCount; i++)
        if (id->pPresentIds[i] && (!info->pResults || info->pResults[i] >= 0))
            next_wait( device, info->pSwapchains[i], id->pPresentIds[i], 100 * 1000 * 1000 );
```

That confirms the cause is the ordering between the host present and `client_surface_present()`.

## Possible fix

For offscreen client surfaces, win32u could make sure the host present has completed before `client_surface_present()`. One option is to enable `VK_KHR_present_id`/`VK_KHR_present_wait` itself when the driver supports them, tag the present and call `vkWaitForPresentKHR`. A fallback is needed when the driver does not support them, or the offscreen copy could be done through Vulkan instead of XComposite. I haven't written a Wine patch; I'm happy to test one.
