{
  description = "Lean Android dev: adb + minimal SDK for builds";

  inputs = {
    nixpkgs.url    = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };

        androidBuildToolsVersion = "35.0.0";
        # androidNdkVersion        = ;

        # Compose a *minimal* SDK: one platform + one build-tools, no emulator/NDK/images.
        androidMin = pkgs.androidenv.composeAndroidPackages {
          platformVersions    = [ "34" "35" ];
          buildToolsVersions  = [ androidBuildToolsVersion ];
          ndkVersions         = [ "27.1.12297006" "27.0.12077973" ];
          cmakeVersions       = [ "3.22.1" ];
          includeNDK          = true;
        };

        android = androidMin.androidsdk;
        jdk = pkgs.jdk17_headless;          # smaller than full JDK
      in {
        # Use this for *building*: nix develop
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            android-tools   # adb/fastboot (small)
            android         # minimal SDK (aapt/aapt2/apksigner/zipalign, etc.)
            git git-lfs gh
            nodejs_20 pnpm jq
            jdk
          ];

          ANDROID_HOME     = "${android}/libexec/android-sdk";
          ANDROID_SDK_ROOT = "${android}/libexec/android-sdk";
          JAVA_HOME        = jdk;

          GRADLE_OPTS = ''
            -Dorg.gradle.project.android.defaults.buildfeatures.prefab=true
            -Dorg.gradle.project.android.prefabVersion=2.1.0
            -Dorg.gradle.project.android.aapt2FromMavenOverride=${android}/libexec/android-sdk/build-tools/${androidBuildToolsVersion}/aapt2
          '';

          shellHook = ''
            export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
            export LD_LIBRARY_PATH="${pkgs.libxml2.out}/lib:$LD_LIBRARY_PATH"

            # Some builds still read these; harmless to set explicitly
            export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/27.0.12077973"
            export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"
          '';
        };

        # Keep your profile install *tiny*: no SDK here.
        packages.devtools = pkgs.symlinkJoin {
          name  = "devtools";
          paths = with pkgs; [
            git git-lfs gh nodejs_20 pnpm jq jdk
            android-tools   # adb only, stays small
            android
          ];
        };

        # If you ever want to install the SDK explicitly: nix profile add .#android-sdk
        packages.android-sdk = android;
      });
}
