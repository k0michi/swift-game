// One webgpu.h over two implementations: the browser's WebGPU (Emdawnwebgpu,
// its functions renamed by make-emdawn.py) and the WebGL 2 fork of Dawn
// (dawn::native). The program calls wgpu* as usual, through Dawn's dawn_proc.
//
// requestAdapter chooses the implementation: the fork for backendType
// OpenGLES, and otherwise the browser's WebGPU, falling back to the fork when
// it has no adapter. The first adapter commits its implementation, and from
// then on dawn_proc calls it directly. Only instances and surfaces, which
// exist before an adapter, are wrapped here: an instance holds one of each
// implementation, and a surface creates its inner surface once committed, so
// that the canvas only ever gets the context of one.
//
// ?backend=webgpu or ?backend=webgl2 in the page's URL forces one.
#include <dawn/dawn_proc.h>
#include <dawn/native/DawnNative.h>
#include <emscripten/em_js.h>

#include <cstring>
#include <memory>
#include <string>
#include <unordered_set>
#include <vector>

const DawnProcTable& EmdawnGetProcs();

namespace {

enum class Implementation { None, WebGPU, WebGL2 };

const DawnProcTable* gWebGPU = nullptr;
const DawnProcTable* gWebGL2 = nullptr;
// The table dawn_proc calls: the committed implementation, with the functions below in place of
// its instance and surface functions.
DawnProcTable gFacade = {};
Implementation gCommitted = Implementation::None;

EM_JS(int, ForcedBackend, (), {
    const backend = new URLSearchParams(location.search).get('backend');
    return backend === 'webgpu' ? 1 : backend === 'webgl2' ? 2 : 0;
});

const DawnProcTable& Committed() {
    return gCommitted == Implementation::WebGPU ? *gWebGPU : *gWebGL2;
}

struct Instance {
    int refs = 1;
    WGPUInstance webgpu = nullptr;
    WGPUInstance webgl2 = nullptr;
};

struct Surface {
    int refs = 1;
    Instance* instance = nullptr;
    std::string selector;
    std::string label;
    WGPUSurface webgpu = nullptr;
    WGPUSurface webgl2 = nullptr;
};

// The handles given out, to tell them from the implementations' own (wgpuAdapterGetInstance
// returns the facade's, but a program may still pass others).
std::unordered_set<void*> gInstances;
std::unordered_set<void*> gSurfaces;
Instance* gLastInstance = nullptr;

Instance* AsInstance(WGPUInstance instance) {
    return gInstances.count(instance) ? reinterpret_cast<Instance*>(instance) : nullptr;
}

Surface* AsSurface(WGPUSurface surface) {
    return gSurfaces.count(surface) ? reinterpret_cast<Surface*>(surface) : nullptr;
}

WGPUInstance Inner(Instance* instance) {
    return gCommitted == Implementation::WebGPU ? instance->webgpu : instance->webgl2;
}

WGPUStringView View(const std::string& text) {
    return {text.data(), text.size()};
}

// The surface of |implementation|, created when first needed.
WGPUSurface InnerSurface(Surface* surface, Implementation implementation) {
    const bool webgpu = implementation == Implementation::WebGPU;
    WGPUSurface& inner = webgpu ? surface->webgpu : surface->webgl2;
    if (inner == nullptr) {
        WGPUEmscriptenSurfaceSourceCanvasHTMLSelector canvas = {};
        canvas.chain.sType = WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector;
        canvas.selector = View(surface->selector);
        WGPUSurfaceDescriptor descriptor = {};
        descriptor.nextInChain = &canvas.chain;
        descriptor.label = View(surface->label);
        const DawnProcTable& procs = webgpu ? *gWebGPU : *gWebGL2;
        inner = procs.instanceCreateSurface(
            webgpu ? surface->instance->webgpu : surface->instance->webgl2, &descriptor);
    }
    return inner;
}

void ApplyOverrides(DawnProcTable& procs);

void Commit(Implementation implementation) {
    if (gCommitted != Implementation::None) {
        return;
    }
    gCommitted = implementation;
    gFacade = Committed();
    ApplyOverrides(gFacade);
    dawnProcSetProcs(&gFacade);
}

// Adapter requests, which may try both implementations, report through their own futures. Their
// IDs are far above those of the implementations.
constexpr uint64_t kFirstFacadeFuture = uint64_t(1) << 62;
uint64_t gNextFuture = kFirstFacadeFuture;

struct AdapterRequest {
    uint64_t future;
    Instance* instance;
    WGPURequestAdapterCallbackInfo callbackInfo;
    WGPURequestAdapterOptions options;
    Surface* compatibleSurface;
    bool ready = false;
    bool delivered = false;
    WGPURequestAdapterStatus status = WGPURequestAdapterStatus_Error;
    WGPUAdapter adapter = nullptr;
    std::string message;
};
std::vector<std::unique_ptr<AdapterRequest>> gRequests;

void Deliver(AdapterRequest* request) {
    if (request->delivered) {
        return;
    }
    request->delivered = true;
    request->callbackInfo.callback(request->status, request->adapter, View(request->message),
                                   request->callbackInfo.userdata1,
                                   request->callbackInfo.userdata2);
}

void Finish(AdapterRequest* request,
            WGPURequestAdapterStatus status,
            WGPUAdapter adapter,
            WGPUStringView message) {
    request->ready = true;
    request->status = status;
    request->adapter = adapter;
    request->message = message.data ? std::string(message.data, message.length == WGPU_STRLEN
                                                                    ? strlen(message.data)
                                                                    : message.length)
                                    : std::string();
    if (request->callbackInfo.mode == WGPUCallbackMode_AllowSpontaneous) {
        Deliver(request);
    }
}

void RequestFromWebGL2(AdapterRequest* request) {
    if (request->instance->webgl2 == nullptr) {
        Finish(request, WGPURequestAdapterStatus_Unavailable, nullptr,
               {"WebGL 2 is not available", WGPU_STRLEN});
        return;
    }
    WGPURequestAdapterOptions options = request->options;
    options.backendType = WGPUBackendType_OpenGLES;
    options.compatibleSurface =
        request->compatibleSurface ? InnerSurface(request->compatibleSurface, Implementation::WebGL2)
                                   : nullptr;
    WGPURequestAdapterCallbackInfo callbackInfo = {};
    callbackInfo.mode = WGPUCallbackMode_AllowSpontaneous;
    callbackInfo.userdata1 = request;
    callbackInfo.callback = [](WGPURequestAdapterStatus status, WGPUAdapter adapter,
                               WGPUStringView message, void* userdata1, void*) {
        auto* request = static_cast<AdapterRequest*>(userdata1);
        if (adapter != nullptr) {
            Commit(Implementation::WebGL2);
        }
        Finish(request, status, adapter, message);
    };
    gWebGL2->instanceRequestAdapter(request->instance->webgl2, &options, callbackInfo);
}

void RequestFromWebGPU(AdapterRequest* request, bool fallBack) {
    if (request->instance->webgpu == nullptr) {
        if (fallBack) {
            RequestFromWebGL2(request);
        } else {
            Finish(request, WGPURequestAdapterStatus_Unavailable, nullptr,
                   {"WebGPU is not available", WGPU_STRLEN});
        }
        return;
    }
    WGPURequestAdapterOptions options = request->options;
    // The browser chooses its backend, and has no surfaces to be compatible with.
    options.backendType = WGPUBackendType_Undefined;
    options.compatibleSurface = nullptr;
    WGPURequestAdapterCallbackInfo callbackInfo = {};
    callbackInfo.mode = WGPUCallbackMode_AllowSpontaneous;
    callbackInfo.userdata1 = request;
    callbackInfo.userdata2 = reinterpret_cast<void*>(uintptr_t(fallBack));
    callbackInfo.callback = [](WGPURequestAdapterStatus status, WGPUAdapter adapter,
                               WGPUStringView message, void* userdata1, void* userdata2) {
        auto* request = static_cast<AdapterRequest*>(userdata1);
        if (adapter != nullptr) {
            Commit(Implementation::WebGPU);
            Finish(request, status, adapter, message);
        } else if (userdata2 != nullptr && gCommitted == Implementation::None) {
            RequestFromWebGL2(request);
        } else {
            Finish(request, status, adapter, message);
        }
    };
    gWebGPU->instanceRequestAdapter(request->instance->webgpu, &options, callbackInfo);
}

// Instance functions.

WGPUInstance CreateInstance(const WGPUInstanceDescriptor* descriptor) {
    auto* instance = new Instance();
    if (ForcedBackend() != 2) {
        instance->webgpu = gWebGPU->createInstance(descriptor);
    }
    if (ForcedBackend() != 1) {
        instance->webgl2 = gWebGL2->createInstance(descriptor);
    }
    gInstances.insert(instance);
    gLastInstance = instance;
    return reinterpret_cast<WGPUInstance>(instance);
}

void InstanceAddRef(WGPUInstance handle) {
    if (Instance* instance = AsInstance(handle)) {
        instance->refs++;
        return;
    }
    Committed().instanceAddRef(handle);
}

void InstanceRelease(WGPUInstance handle) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        Committed().instanceRelease(handle);
        return;
    }
    if (--instance->refs > 0) {
        return;
    }
    if (instance->webgpu) {
        gWebGPU->instanceRelease(instance->webgpu);
    }
    if (instance->webgl2) {
        gWebGL2->instanceRelease(instance->webgl2);
    }
    gInstances.erase(instance);
    if (gLastInstance == instance) {
        gLastInstance = nullptr;
    }
    delete instance;
}

WGPUSurface InstanceCreateSurface(WGPUInstance handle, const WGPUSurfaceDescriptor* descriptor) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        return Committed().instanceCreateSurface(handle, descriptor);
    }
    auto* surface = new Surface();
    surface->instance = instance;
    instance->refs++;
    if (descriptor->label.data) {
        surface->label = std::string(descriptor->label.data, descriptor->label.length == WGPU_STRLEN
                                                                 ? strlen(descriptor->label.data)
                                                                 : descriptor->label.length);
    }
    for (const WGPUChainedStruct* chain = descriptor->nextInChain; chain; chain = chain->next) {
        if (chain->sType == WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector) {
            const auto* canvas =
                reinterpret_cast<const WGPUEmscriptenSurfaceSourceCanvasHTMLSelector*>(chain);
            surface->selector =
                std::string(canvas->selector.data, canvas->selector.length == WGPU_STRLEN
                                                       ? strlen(canvas->selector.data)
                                                       : canvas->selector.length);
        }
    }
    gSurfaces.insert(surface);
    return reinterpret_cast<WGPUSurface>(surface);
}

void InstanceGetWGSLLanguageFeatures(WGPUInstance handle,
                                     WGPUSupportedWGSLLanguageFeatures* features) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        Committed().instanceGetWGSLLanguageFeatures(handle, features);
    } else if (gCommitted != Implementation::None) {
        Committed().instanceGetWGSLLanguageFeatures(Inner(instance), features);
    } else if (instance->webgpu) {
        gWebGPU->instanceGetWGSLLanguageFeatures(instance->webgpu, features);
    } else {
        gWebGL2->instanceGetWGSLLanguageFeatures(instance->webgl2, features);
    }
}

WGPUBool InstanceHasWGSLLanguageFeature(WGPUInstance handle, WGPUWGSLLanguageFeatureName feature) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        return Committed().instanceHasWGSLLanguageFeature(handle, feature);
    } else if (gCommitted != Implementation::None) {
        return Committed().instanceHasWGSLLanguageFeature(Inner(instance), feature);
    } else if (instance->webgpu) {
        return gWebGPU->instanceHasWGSLLanguageFeature(instance->webgpu, feature);
    }
    return gWebGL2->instanceHasWGSLLanguageFeature(instance->webgl2, feature);
}

void InstanceProcessEvents(WGPUInstance handle) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        Committed().instanceProcessEvents(handle);
        return;
    }
    if (instance->webgpu) {
        gWebGPU->instanceProcessEvents(instance->webgpu);
    }
    if (instance->webgl2) {
        gWebGL2->instanceProcessEvents(instance->webgl2);
    }
    for (auto& request : gRequests) {
        if (request->ready && request->callbackInfo.mode == WGPUCallbackMode_AllowProcessEvents) {
            Deliver(request.get());
        }
    }
    std::erase_if(gRequests, [](const auto& request) { return request->delivered; });
}

WGPUFuture InstanceRequestAdapter(WGPUInstance handle,
                                  const WGPURequestAdapterOptions* options,
                                  WGPURequestAdapterCallbackInfo callbackInfo) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        return Committed().instanceRequestAdapter(handle, options, callbackInfo);
    }
    auto request = std::make_unique<AdapterRequest>();
    request->future = gNextFuture++;
    request->instance = instance;
    request->callbackInfo = callbackInfo;
    request->options = options ? *options : WGPURequestAdapterOptions{};
    // Chained options may not outlive the call, and neither implementation needs them here.
    request->options.nextInChain = nullptr;
    request->compatibleSurface = options ? AsSurface(options->compatibleSurface) : nullptr;
    AdapterRequest* pending = request.get();
    gRequests.push_back(std::move(request));
    const WGPUFuture future = {pending->future};

    const int forced = ForcedBackend();
    const bool wantsWebGL2 =
        forced == 2 || gCommitted == Implementation::WebGL2 ||
        (gCommitted == Implementation::None && forced == 0 && options &&
         options->backendType == WGPUBackendType_OpenGLES);
    if (wantsWebGL2) {
        RequestFromWebGL2(pending);
    } else {
        RequestFromWebGPU(pending, forced == 0 && gCommitted == Implementation::None);
    }
    return future;
}

WGPUWaitStatus InstanceWaitAny(WGPUInstance handle,
                               size_t futureCount,
                               WGPUFutureWaitInfo* futures,
                               uint64_t timeoutNS) {
    Instance* instance = AsInstance(handle);
    if (instance == nullptr) {
        return Committed().instanceWaitAny(handle, futureCount, futures, timeoutNS);
    }
    bool completed = false;
    std::vector<size_t> others;
    for (size_t i = 0; i < futureCount; i++) {
        if (futures[i].future.id < kFirstFacadeFuture) {
            others.push_back(i);
            continue;
        }
        for (auto& request : gRequests) {
            if (request->future == futures[i].future.id && request->ready) {
                Deliver(request.get());
                futures[i].completed = true;
                completed = true;
            }
        }
    }
    std::erase_if(gRequests, [](const auto& request) { return request->delivered; });
    if (others.empty() || gCommitted == Implementation::None) {
        return completed ? WGPUWaitStatus_Success : WGPUWaitStatus_TimedOut;
    }
    std::vector<WGPUFutureWaitInfo> inner;
    for (size_t i : others) {
        inner.push_back(futures[i]);
    }
    WGPUWaitStatus status = Committed().instanceWaitAny(Inner(instance), inner.size(),
                                                        inner.data(), completed ? 0 : timeoutNS);
    for (size_t j = 0; j < others.size(); j++) {
        futures[others[j]].completed = inner[j].completed;
    }
    return completed && status == WGPUWaitStatus_TimedOut ? WGPUWaitStatus_Success : status;
}

WGPUInstance AdapterGetInstance(WGPUAdapter adapter) {
    if (gLastInstance != nullptr) {
        gLastInstance->refs++;
        return reinterpret_cast<WGPUInstance>(gLastInstance);
    }
    return Committed().adapterGetInstance(adapter);
}

// Surface functions. Before an implementation is committed, there is nothing to configure.

void SurfaceAddRef(WGPUSurface handle) {
    if (Surface* surface = AsSurface(handle)) {
        surface->refs++;
        return;
    }
    Committed().surfaceAddRef(handle);
}

void SurfaceRelease(WGPUSurface handle) {
    Surface* surface = AsSurface(handle);
    if (surface == nullptr) {
        Committed().surfaceRelease(handle);
        return;
    }
    if (--surface->refs > 0) {
        return;
    }
    if (surface->webgpu) {
        gWebGPU->surfaceRelease(surface->webgpu);
    }
    if (surface->webgl2) {
        gWebGL2->surfaceRelease(surface->webgl2);
    }
    gSurfaces.erase(surface);
    InstanceRelease(reinterpret_cast<WGPUInstance>(surface->instance));
    delete surface;
}

WGPUSurface CommittedSurface(WGPUSurface handle) {
    Surface* surface = AsSurface(handle);
    if (surface == nullptr || gCommitted == Implementation::None) {
        return surface ? nullptr : handle;
    }
    return InnerSurface(surface, gCommitted);
}

void SurfaceConfigure(WGPUSurface handle, const WGPUSurfaceConfiguration* config) {
    if (WGPUSurface inner = CommittedSurface(handle)) {
        Committed().surfaceConfigure(inner, config);
    }
}

WGPUStatus SurfaceGetCapabilities(WGPUSurface handle,
                                  WGPUAdapter adapter,
                                  WGPUSurfaceCapabilities* capabilities) {
    WGPUSurface inner = CommittedSurface(handle);
    return inner ? Committed().surfaceGetCapabilities(inner, adapter, capabilities)
                 : WGPUStatus_Error;
}

void SurfaceGetCurrentTexture(WGPUSurface handle, WGPUSurfaceTexture* surfaceTexture) {
    if (WGPUSurface inner = CommittedSurface(handle)) {
        Committed().surfaceGetCurrentTexture(inner, surfaceTexture);
        return;
    }
    *surfaceTexture = {};
    surfaceTexture->status = WGPUSurfaceGetCurrentTextureStatus_Error;
}

WGPUStatus SurfacePresent(WGPUSurface handle) {
    WGPUSurface inner = CommittedSurface(handle);
    return inner ? Committed().surfacePresent(inner) : WGPUStatus_Error;
}

void SurfaceSetLabel(WGPUSurface handle, WGPUStringView label) {
    if (Surface* surface = AsSurface(handle)) {
        surface->label = label.data ? std::string(label.data, label.length == WGPU_STRLEN
                                                                  ? strlen(label.data)
                                                                  : label.length)
                                    : std::string();
    }
    if (WGPUSurface inner = CommittedSurface(handle)) {
        Committed().surfaceSetLabel(inner, label);
    }
}

void SurfaceUnconfigure(WGPUSurface handle) {
    if (WGPUSurface inner = CommittedSurface(handle)) {
        Committed().surfaceUnconfigure(inner);
    }
}

void ApplyOverrides(DawnProcTable& procs) {
    procs.createInstance = CreateInstance;
    procs.instanceAddRef = InstanceAddRef;
    procs.instanceRelease = InstanceRelease;
    procs.instanceCreateSurface = InstanceCreateSurface;
    procs.instanceGetWGSLLanguageFeatures = InstanceGetWGSLLanguageFeatures;
    procs.instanceHasWGSLLanguageFeature = InstanceHasWGSLLanguageFeature;
    procs.instanceProcessEvents = InstanceProcessEvents;
    procs.instanceRequestAdapter = InstanceRequestAdapter;
    procs.instanceWaitAny = InstanceWaitAny;
    procs.adapterGetInstance = AdapterGetInstance;
    procs.surfaceAddRef = SurfaceAddRef;
    procs.surfaceRelease = SurfaceRelease;
    procs.surfaceConfigure = SurfaceConfigure;
    procs.surfaceGetCapabilities = SurfaceGetCapabilities;
    procs.surfaceGetCurrentTexture = SurfaceGetCurrentTexture;
    procs.surfacePresent = SurfacePresent;
    procs.surfaceSetLabel = SurfaceSetLabel;
    procs.surfaceUnconfigure = SurfaceUnconfigure;
}

// Before main(): until an adapter commits an implementation, functions other than the ones above
// go to the fork, which has them all.
struct Installer {
    Installer() {
        gWebGPU = &EmdawnGetProcs();
        gWebGL2 = &dawn::native::GetProcs();
        gFacade = *gWebGL2;
        ApplyOverrides(gFacade);
        dawnProcSetProcs(&gFacade);
    }
} gInstaller;

}  // namespace
