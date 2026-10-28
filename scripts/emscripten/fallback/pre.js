// Before main(), chooses between the browser's WebGPU and the WebGL 2 fork of Dawn: WebGPU when
// the browser has a compatibility-mode adapter. ?backend=webgl2 or ?backend=webgpu forces one.
Module['preRun'] = Module['preRun'] || [];
Module['preRun'].push(() => {
  addRunDependency('choose-webgpu-backend');
  (async () => {
    const forced = new URLSearchParams(location.search).get('backend');
    let webgpu = false;
    if (forced) {
      webgpu = forced === 'webgpu';
    } else {
      try {
        webgpu = !!(navigator.gpu && await navigator.gpu.requestAdapter({ featureLevel: 'compatibility' }));
      } catch (e) {
        webgpu = false;
      }
    }
    Module['webgpuBackend'] = webgpu ? 'webgpu' : 'webgl2';
    removeRunDependency('choose-webgpu-backend');
  })();
});
