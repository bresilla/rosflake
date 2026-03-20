{ pkgs, nixgl, nvidiaVersion, nvidiaHash }:
let
  haveNvidiaPinned = nvidiaVersion != "" && nvidiaHash != "";

  nixglFixed =
    if haveNvidiaPinned then
      pkgs.callPackage (nixgl.outPath + "/default.nix") {
        inherit nvidiaVersion nvidiaHash;
      }
    else
      null;

  nixGLNvidiaWrapper =
    if haveNvidiaPinned then
      pkgs.writeShellScriptBin "nixGLNvidia" ''
        real="$(echo ${nixglFixed.nixGLNvidia}/bin/nixGLNvidia-*)"
        exec "$real" "$@"
      ''
    else
      null;

  nixVulkanNvidiaWrapper =
    if haveNvidiaPinned then
      pkgs.writeShellScriptBin "nixVulkanNvidia" ''
        real="$(echo ${nixglFixed.nixVulkanNvidia}/bin/nixVulkanNvidia-*)"
        exec "$real" "$@"
      ''
    else
      null;
in
{
  inherit haveNvidiaPinned;

  packages =
    pkgs.lib.optionals haveNvidiaPinned [
      nixglFixed.nixGLNvidia
      nixglFixed.nixVulkanNvidia
      nixGLNvidiaWrapper
      nixVulkanNvidiaWrapper
    ];

  shellHook = ''
    if [ -n "$NIXGL_NVIDIA_VERSION" ] && [ -n "$NIXGL_NVIDIA_HASH" ]; then
        export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/nvidia_icd.json
        export VK_LOADER_LAYERS_DISABLE='*MESA_device_select*'
        export ALSA_PLUGIN_DIR=${pkgs.pipewire}/lib/alsa-lib

        echo "nixGL Nvidia pinned to $NIXGL_NVIDIA_VERSION"
        echo "Using Vulkan driver manifest: $VK_DRIVER_FILES"
        echo "Using ALSA plugins from: $ALSA_PLUGIN_DIR"
    else
        echo "nixGL Nvidia not configured"
    fi
  '';
}
