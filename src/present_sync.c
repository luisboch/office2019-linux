/*
 * VK_LAYER_WINE_present_sync
 *
 * Wine renders Vulkan in child windows offscreen: after vkQueuePresentKHR
 * returns, win32u copies the (XComposite-redirected) client window into the
 * toplevel window.  Mesa's X11 WSI on Xwayland only queues the image there and
 * presents it later from its own thread, so the copy picks up the previous
 * frame and the window shows everything one present late (Office: cells not
 * cleared after Delete, hover highlight lagging behind the cursor).
 *
 * This layer makes vkQueuePresentKHR wait until the frame was really
 * presented (vkWaitForPresentKHR) when the application passed a present id
 * and enabled VK_KHR_present_wait, as DXVK does.
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later (same terms as Wine)
 */

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>

#define LAYER_NAME "VK_LAYER_WINE_present_sync"
#define EXPORT __attribute__((visibility("default")))
#define MAX_OBJECTS 64

static uint64_t wait_timeout_ns = 100 * 1000 * 1000;

struct instance_data
{
    void *key;
    VkInstance instance;
    PFN_vkGetInstanceProcAddr next_gipa;
    PFN_vkDestroyInstance next_destroy;
};

struct device_data
{
    void *key;
    VkDevice device;
    PFN_vkGetDeviceProcAddr next_gdpa;
    PFN_vkDestroyDevice next_destroy;
    PFN_vkQueuePresentKHR next_present;
    PFN_vkWaitForPresentKHR next_wait;
    int present_wait;
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct instance_data instances[MAX_OBJECTS];
static struct device_data devices[MAX_OBJECTS];

static void *dispatch_key( const void *handle )
{
    return *(void **)handle;
}

static struct instance_data *find_instance( void *key )
{
    for (int i = 0; i < MAX_OBJECTS; i++) if (instances[i].key == key) return &instances[i];
    return NULL;
}

static struct device_data *find_device( void *key )
{
    for (int i = 0; i < MAX_OBJECTS; i++) if (devices[i].key == key) return &devices[i];
    return NULL;
}

static const void *find_struct( const void *chain, VkStructureType type )
{
    for (const VkBaseInStructure *s = chain; s; s = s->pNext) if (s->sType == type) return s;
    return NULL;
}

static VKAPI_ATTR VkResult VKAPI_CALL layer_CreateInstance( const VkInstanceCreateInfo *info,
                                                            const VkAllocationCallbacks *allocator,
                                                            VkInstance *instance )
{
    VkLayerInstanceCreateInfo *link = (VkLayerInstanceCreateInfo *)info->pNext;
    PFN_vkGetInstanceProcAddr next_gipa;
    PFN_vkCreateInstance next_create;
    struct instance_data *data;
    VkResult res;

    while (link && !(link->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO && link->function == VK_LAYER_LINK_INFO))
        link = (VkLayerInstanceCreateInfo *)link->pNext;
    if (!link) return VK_ERROR_INITIALIZATION_FAILED;

    next_gipa = link->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    link->u.pLayerInfo = link->u.pLayerInfo->pNext;
    next_create = (PFN_vkCreateInstance)next_gipa( VK_NULL_HANDLE, "vkCreateInstance" );
    if ((res = next_create( info, allocator, instance )) != VK_SUCCESS) return res;

    pthread_mutex_lock( &lock );
    if ((data = find_instance( NULL )))
    {
        data->key = dispatch_key( *instance );
        data->instance = *instance;
        data->next_gipa = next_gipa;
        data->next_destroy = (PFN_vkDestroyInstance)next_gipa( *instance, "vkDestroyInstance" );
    }
    pthread_mutex_unlock( &lock );
    return data ? VK_SUCCESS : VK_ERROR_OUT_OF_HOST_MEMORY;
}

static VKAPI_ATTR void VKAPI_CALL layer_DestroyInstance( VkInstance instance, const VkAllocationCallbacks *allocator )
{
    PFN_vkDestroyInstance next_destroy = NULL;
    struct instance_data *data;

    pthread_mutex_lock( &lock );
    if ((data = find_instance( dispatch_key( instance ) )))
    {
        next_destroy = data->next_destroy;
        memset( data, 0, sizeof(*data) );
    }
    pthread_mutex_unlock( &lock );
    if (next_destroy) next_destroy( instance, allocator );
}

static int has_extension( const VkDeviceCreateInfo *info, const char *name )
{
    for (uint32_t i = 0; i < info->enabledExtensionCount; i++)
        if (!strcmp( info->ppEnabledExtensionNames[i], name )) return 1;
    return 0;
}

static VKAPI_ATTR VkResult VKAPI_CALL layer_CreateDevice( VkPhysicalDevice physical_device,
                                                          const VkDeviceCreateInfo *info,
                                                          const VkAllocationCallbacks *allocator,
                                                          VkDevice *device )
{
    VkLayerDeviceCreateInfo *link = (VkLayerDeviceCreateInfo *)info->pNext;
    const VkPhysicalDevicePresentWaitFeaturesKHR *wait_features;
    PFN_vkGetInstanceProcAddr next_gipa;
    PFN_vkGetDeviceProcAddr next_gdpa;
    PFN_vkCreateDevice next_create;
    struct device_data *data;
    VkResult res;

    while (link && !(link->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO && link->function == VK_LAYER_LINK_INFO))
        link = (VkLayerDeviceCreateInfo *)link->pNext;
    if (!link) return VK_ERROR_INITIALIZATION_FAILED;

    next_gipa = link->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    next_gdpa = link->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    link->u.pLayerInfo = link->u.pLayerInfo->pNext;
    next_create = (PFN_vkCreateDevice)next_gipa( VK_NULL_HANDLE, "vkCreateDevice" );
    if ((res = next_create( physical_device, info, allocator, device )) != VK_SUCCESS) return res;

    wait_features = find_struct( info->pNext, VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PRESENT_WAIT_FEATURES_KHR );

    pthread_mutex_lock( &lock );
    if ((data = find_device( NULL )))
    {
        data->key = dispatch_key( *device );
        data->device = *device;
        data->next_gdpa = next_gdpa;
        data->next_destroy = (PFN_vkDestroyDevice)next_gdpa( *device, "vkDestroyDevice" );
        data->next_present = (PFN_vkQueuePresentKHR)next_gdpa( *device, "vkQueuePresentKHR" );
        data->next_wait = (PFN_vkWaitForPresentKHR)next_gdpa( *device, "vkWaitForPresentKHR" );
        data->present_wait = data->next_wait && wait_features && wait_features->presentWait &&
                             has_extension( info, VK_KHR_PRESENT_WAIT_EXTENSION_NAME ) &&
                             has_extension( info, VK_KHR_PRESENT_ID_EXTENSION_NAME );
    }
    pthread_mutex_unlock( &lock );
    return data ? VK_SUCCESS : VK_ERROR_OUT_OF_HOST_MEMORY;
}

static VKAPI_ATTR void VKAPI_CALL layer_DestroyDevice( VkDevice device, const VkAllocationCallbacks *allocator )
{
    PFN_vkDestroyDevice next_destroy = NULL;
    struct device_data *data;

    pthread_mutex_lock( &lock );
    if ((data = find_device( dispatch_key( device ) )))
    {
        next_destroy = data->next_destroy;
        memset( data, 0, sizeof(*data) );
    }
    pthread_mutex_unlock( &lock );
    if (next_destroy) next_destroy( device, allocator );
}

static VKAPI_ATTR VkResult VKAPI_CALL layer_QueuePresentKHR( VkQueue queue, const VkPresentInfoKHR *info )
{
    const VkPresentIdKHR *ids;
    struct device_data data;
    struct device_data *found;
    VkResult res;

    pthread_mutex_lock( &lock );
    if ((found = find_device( dispatch_key( queue ) ))) data = *found;
    pthread_mutex_unlock( &lock );
    if (!found) return VK_ERROR_DEVICE_LOST;

    res = data.next_present( queue, info );
    if (res < VK_SUCCESS || !data.present_wait) return res;
    if (!(ids = find_struct( info->pNext, VK_STRUCTURE_TYPE_PRESENT_ID_KHR )) || !ids->pPresentIds) return res;

    for (uint32_t i = 0; i < info->swapchainCount && i < ids->swapchainCount; i++)
    {
        if (!ids->pPresentIds[i]) continue;
        if (info->pResults && info->pResults[i] < VK_SUCCESS) continue;
        data.next_wait( data.device, info->pSwapchains[i], ids->pPresentIds[i], wait_timeout_ns );
    }
    return res;
}

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL layer_GetDeviceProcAddr( VkDevice device, const char *name );

static PFN_vkVoidFunction intercept_device( const char *name )
{
    if (!strcmp( name, "vkGetDeviceProcAddr" )) return (PFN_vkVoidFunction)layer_GetDeviceProcAddr;
    if (!strcmp( name, "vkDestroyDevice" )) return (PFN_vkVoidFunction)layer_DestroyDevice;
    if (!strcmp( name, "vkQueuePresentKHR" )) return (PFN_vkVoidFunction)layer_QueuePresentKHR;
    return NULL;
}

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL layer_GetDeviceProcAddr( VkDevice device, const char *name )
{
    PFN_vkGetDeviceProcAddr next_gdpa = NULL;
    PFN_vkVoidFunction func;
    struct device_data *data;

    if ((func = intercept_device( name ))) return func;

    pthread_mutex_lock( &lock );
    if ((data = find_device( dispatch_key( device ) ))) next_gdpa = data->next_gdpa;
    pthread_mutex_unlock( &lock );
    return next_gdpa ? next_gdpa( device, name ) : NULL;
}

EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL layer_GetInstanceProcAddr( VkInstance instance, const char *name )
{
    PFN_vkGetInstanceProcAddr next_gipa = NULL;
    PFN_vkVoidFunction func;
    struct instance_data *data;

    if (!strcmp( name, "vkGetInstanceProcAddr" )) return (PFN_vkVoidFunction)layer_GetInstanceProcAddr;
    if (!strcmp( name, "vkCreateInstance" )) return (PFN_vkVoidFunction)layer_CreateInstance;
    if (!strcmp( name, "vkDestroyInstance" )) return (PFN_vkVoidFunction)layer_DestroyInstance;
    if (!strcmp( name, "vkCreateDevice" )) return (PFN_vkVoidFunction)layer_CreateDevice;
    if ((func = intercept_device( name ))) return func;
    if (!instance) return NULL;

    pthread_mutex_lock( &lock );
    if ((data = find_instance( dispatch_key( instance ) ))) next_gipa = data->next_gipa;
    pthread_mutex_unlock( &lock );
    return next_gipa ? next_gipa( instance, name ) : NULL;
}

EXPORT VKAPI_ATTR VkResult VKAPI_CALL layer_NegotiateLoaderLayerInterfaceVersion( VkNegotiateLayerInterface *iface )
{
    const char *env;

    if (iface->loaderLayerInterfaceVersion > 2) iface->loaderLayerInterfaceVersion = 2;
    iface->pfnGetInstanceProcAddr = layer_GetInstanceProcAddr;
    iface->pfnGetDeviceProcAddr = layer_GetDeviceProcAddr;
    iface->pfnGetPhysicalDeviceProcAddr = NULL;

    if ((env = getenv( "WINE_PRESENT_SYNC_TIMEOUT_MS" ))) wait_timeout_ns = strtoull( env, NULL, 10 ) * 1000 * 1000;
    return VK_SUCCESS;
}
