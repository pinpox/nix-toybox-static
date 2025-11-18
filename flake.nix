{
  description = "Toybox: all-in-one Linux command line";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    toybox = {
      url = "github:landley/toybox";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, toybox, ... }:
    let
      # Unified function to build toybox for any host/target/tool combination
      mkToybox =
        hostPlatform: targetPlatform: tool:
        let
          # Import nixpkgs for the host platform
          pkgs = import nixpkgs { system = hostPlatform; };

          # Get cross-compilation pkgs if needed
          crossPkgs =
            if hostPlatform == targetPlatform then
              pkgs
            else
              import nixpkgs {
                system = hostPlatform;
                crossSystem = nixpkgs.lib.systems.examples.${targetPlatform} or { config = targetPlatform; };
              };

          # Determine the target platform info
          targetPlatformParsed = nixpkgs.lib.systems.parse.mkSystemFromString targetPlatform;
          isLinuxTarget = targetPlatformParsed.kernel.name == "linux";

          # Use musl for static linking on Linux, regular pkgs for Darwin (static linking not well supported)
          pkgsStatic = if isLinuxTarget then crossPkgs.pkgsMusl else crossPkgs;

          # Determine what to build (toybox or a single command)
          buildTarget = if tool == "toybox" then "toybox" else tool;
          isToybox = tool == "toybox";
        in
        pkgsStatic.stdenv.mkDerivation {
          pname = "toybox${if isToybox then "" else "-${tool}"}${if isLinuxTarget then "" else "-dynamic"}";
          version = "0.8.11";

          src = toybox;

          depsBuildBuild = with pkgs.buildPackages; [
            bash
            gcc
          ];
          nativeBuildInputs = with pkgs.buildPackages; [ bash ];

          buildInputs = with pkgsStatic; [
            libxcrypt
            zlib
            openssl
          ];

          hardeningDisable = [ "fortify" ];

          preConfigure = ''
            patchShebangs scripts/
            ${nixpkgs.lib.optionalString (hostPlatform != targetPlatform) ''
              export HOSTCC=${pkgs.buildPackages.gcc}/bin/gcc
            ''}
          '';

          configurePhase = nixpkgs.lib.optionalString isToybox ''
            runHook preConfigure
            make defconfig
            runHook postConfigure
          '';

          makeFlags = nixpkgs.lib.optionals isLinuxTarget [ "LDFLAGS=--static" ];

          buildPhase = ''
            runHook preBuild
            make $makeFlags ${buildTarget}
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ${buildTarget} $out/bin/${buildTarget}
            runHook postInstall
          '';

          meta = with nixpkgs.lib; {
            description = "Toybox${if isToybox then ": all-in-one command line" else " ${tool} command"}";
            homepage = "http://landley.net/toybox";
            license = licenses.bsd0;
            platforms = platforms.unix;
          };
        };

      # Dynamically discover all available commands from toys/ directory
      commands =
        let
          # Read all subdirectories in toys/
          toysDir = builtins.readDir (toybox + "/toys");
          categories = builtins.filter (name: toysDir.${name} == "directory") (builtins.attrNames toysDir);

          # For each category, read the .c files and extract commands
          getCommandsFromCategory =
            category:
            let
              categoryPath = toybox + "/toys/${category}";
              files = builtins.readDir categoryPath;
              cFiles = builtins.filter (name: nixpkgs.lib.hasSuffix ".c" name) (builtins.attrNames files);

              # Extract command names from a .c file by parsing NEWTOY/OLDTOY macros
              extractCommandsFromFile =
                filename:
                let
                  content = builtins.readFile (categoryPath + "/${filename}");
                  lines = nixpkgs.lib.splitString "\n" content;

                  # Extract command name from NEWTOY/OLDTOY lines
                  extractFromLine =
                    line:
                    let
                      # Match NEWTOY(commandname, or OLDTOY(commandname,
                      matches = builtins.match ".*(NEWTOY|OLDTOY)\\(([a-zA-Z0-9_-]+),.*" line;
                    in
                    if matches != null then builtins.elemAt matches 1 else null;

                  commands = map extractFromLine lines;
                  validCommands = builtins.filter (x: x != null) commands;
                in
                validCommands;

              allCommandsInCategory = nixpkgs.lib.concatMap extractCommandsFromFile cFiles;
            in
            allCommandsInCategory;

          # Get all commands from all categories (excluding "example" category)
          allCommands = nixpkgs.lib.concatMap getCommandsFromCategory (
            builtins.filter (cat: cat != "example") categories
          );

          # Filter out commands that start with "-" (shell aliases/builtins)
          validCommands = builtins.filter (cmd: !nixpkgs.lib.hasPrefix "-" cmd) allCommands;
        in
        validCommands;

      # All host platforms (systems that can build)
      hostPlatforms = nixpkgs.lib.systems.flakeExposed;

      # All target platforms (same as host platforms)
      targetPlatforms = hostPlatforms;

      # All tools to build (toybox + all individual commands)
      allTools = [ "toybox" ] ++ commands;

    in
    {
      # Build the pkgsCross structure: pkgsCross.${hostPlatform}.${targetPlatform}.${tool}
      pkgsCross = builtins.listToAttrs (
        map (hostPlatform: {
          name = hostPlatform;
          value = builtins.listToAttrs (
            map (targetPlatform: {
              name = targetPlatform;
              value = builtins.listToAttrs (
                map (tool: {
                  name = tool;
                  value = mkToybox hostPlatform targetPlatform tool;
                }) allTools
              );
            }) targetPlatforms
          );
        }) hostPlatforms
      );

      # Convenience packages for the current system
      packages = nixpkgs.lib.genAttrs hostPlatforms (
        system:
        let
          # Native builds (same host and target)
          nativePackages = builtins.listToAttrs (
            map (tool: {
              name = tool;
              value = mkToybox system system tool;
            }) allTools
          );
        in
        nativePackages // { default = nativePackages.toybox; }
      );
    };
}
