// Points the wgpu* functions of dawn_proc at the browser's WebGPU (Emdawnwebgpu) or at the
// WebGL 2 fork of Dawn, as pre.js chose, before main().
#include <dawn/dawn_proc.h>
#include <dawn/native/DawnNative.h>
#include <emscripten/em_js.h>

const DawnProcTable& EmdawnGetProcs();

EM_JS(int, ChooseWebGPU, (), { return Module['webgpuBackend'] === 'webgpu' ? 1 : 0; });

namespace {
struct Selector {
    Selector() {
        dawnProcSetProcs(ChooseWebGPU() ? &EmdawnGetProcs() : &dawn::native::GetProcs());
    }
} gSelector;
}  // namespace
