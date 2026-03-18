{
  description = "ros flake";

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    flake-utils.url = "github:numtide/flake-utils";
    nixgl.url = "github:nix-community/nixGL";
  };

  outputs =
    { self, nixpkgs, rust-overlay, flake-utils, nixgl, nix-ros-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) nix-ros-overlay.overlays.default ];

        pkgs = import nixpkgs {
          inherit system overlays;
          config.allowUnfree = true;
        };

        nvidiaVersion = builtins.getEnv "NIXGL_NVIDIA_VERSION";
        nvidiaHash = builtins.getEnv "NIXGL_NVIDIA_HASH";

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
        devShells.default = pkgs.mkShell {
          packages =
            [
              (pkgs.rust-bin.stable.latest.default.override {
                extensions = [ "rust-src" ];
              })
              pkgs.clang
              pkgs.mold
              pkgs.cmake
              pkgs.pkg-config
              pkgs.colcon
              (with pkgs.rosPackages.jazzy; buildEnv {
                paths = [
                  ros-core
                  desktop-full
                ];
              })
            ]
            ++ pkgs.lib.optionals haveNvidiaPinned [
              nixglFixed.nixGLNvidia
              nixglFixed.nixVulkanNvidia
              nixGLNvidiaWrapper
              nixVulkanNvidiaWrapper
            ]
            ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.alsa-lib
              pkgs.alsa-plugins
              pkgs.pipewire
              pkgs.vulkan-loader
              pkgs.vulkan-tools
              pkgs.libudev-zero
              pkgs.libx11
              pkgs.libxcursor
              pkgs.libxrandr
              pkgs.libxkbcommon
              pkgs.wayland
            ];

          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
            pkgs.vulkan-loader
            pkgs.libx11
            pkgs.libxcursor
            pkgs.libxkbcommon
            pkgs.wayland
            pkgs.alsa-lib
            pkgs.alsa-plugins
            pkgs.pipewire
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
        };
      }
    );

  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
