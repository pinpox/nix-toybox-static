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
      # Helper function to generate outputs for all supported systems
      # Using the standard flake-exposed systems from nixpkgs
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;

      # Helper to get nixpkgs for a system
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # Cross-compilation targets - all Linux targets from nixpkgs.lib.systems.examples
      crossTargets = builtins.attrNames (
        nixpkgs.lib.filterAttrs (
          name: system: (system.config or null) != null && (builtins.match ".*-linux.*" system.config != null)
        ) nixpkgs.lib.systems.examples
      );

    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
          # Use musl for static linking on Linux systems
          pkgsStatic = if pkgs.stdenv.isLinux then pkgs.pkgsMusl else pkgs;

          # Base toybox derivation
          toyboxBase = pkgsStatic.stdenv.mkDerivation {
            pname = "toybox";
            version = "0.8.11";

            src = toybox;

            nativeBuildInputs = with pkgs; [ bash ];

            buildInputs = with pkgsStatic; [
              libxcrypt
              zlib
              openssl
            ];

            # Disable hardening features that conflict with toybox
            hardeningDisable = [ "fortify" ];

            preConfigure = ''
              patchShebangs scripts/
            '';

            configurePhase = ''
              runHook preConfigure
              make defconfig
              runHook postConfigure
            '';

            # Build with static linking
            makeFlags = [ "LDFLAGS=--static" ];

            buildPhase = ''
              runHook preBuild
              make $makeFlags toybox
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp toybox $out/bin/toybox
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Toybox: all-in-one Linux command line";
              homepage = "http://landley.net/toybox";
              license = licenses.bsd0;
              platforms = platforms.linux;
              maintainers = [ pinpox ];
            };
          };

          # Function to create a single command derivation
          mkSingleCommand =
            command:
            pkgsStatic.stdenv.mkDerivation {
              pname = "toybox-${command}";
              version = "0.8.11";

              src = toybox;

              nativeBuildInputs = with pkgs; [ bash ];

              buildInputs = with pkgsStatic; [
                libxcrypt
                zlib
                openssl
              ];

              # Disable hardening features that conflict with toybox
              hardeningDisable = [ "fortify" ];

              preConfigure = ''
                patchShebangs scripts/
              '';

              # Build with static linking
              makeFlags = [ "LDFLAGS=--static" ];

              buildPhase = ''
                runHook preBuild
                make $makeFlags ${command}
                runHook postBuild
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin
                cp ${command} $out/bin/${command}
                runHook postInstall
              '';

              meta = with pkgs.lib; {
                description = "Toybox ${command} command";
                homepage = "http://landley.net/toybox";
                license = licenses.bsd0;
                platforms = platforms.linux;
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
                  cFiles = builtins.filter (name: pkgs.lib.hasSuffix ".c" name) (builtins.attrNames files);

                  # Extract command names from a .c file by parsing NEWTOY/OLDTOY macros
                  extractCommandsFromFile =
                    filename:
                    let
                      content = builtins.readFile (categoryPath + "/${filename}");
                      lines = pkgs.lib.splitString "\n" content;

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

                  allCommandsInCategory = pkgs.lib.concatMap extractCommandsFromFile cFiles;
                in
                allCommandsInCategory;

              # Get all commands from all categories (excluding "example" category)
              allCommands = pkgs.lib.concatMap getCommandsFromCategory (
                builtins.filter (cat: cat != "example") categories
              );

              # Filter out commands that start with "-" (shell aliases/builtins)
              validCommands = builtins.filter (cmd: !pkgs.lib.hasPrefix "-" cmd) allCommands;
            in
            validCommands;

          # Create a package set for individual commands
          commandPackages = builtins.listToAttrs (
            map (cmd: {
              name = cmd;
              value = mkSingleCommand cmd;
            }) commands
          );

          # Function to create cross-compiled packages for a target
          mkCrossPackages =
            targetSystem:
            let
              # Get cross-compilation pkgs for the target
              crossPkgs = import nixpkgs {
                inherit system;
                crossSystem = nixpkgs.lib.systems.examples.${targetSystem} or { config = targetSystem; };
              };
              crossPkgsStatic = crossPkgs.pkgsMusl;

              # Cross-compiled toybox base
              crossToyboxBase = crossPkgsStatic.stdenv.mkDerivation {
                pname = "toybox-${targetSystem}";
                version = "0.8.11";

                src = toybox;

                depsBuildBuild = with pkgs.buildPackages; [
                  bash
                  gcc
                ];
                nativeBuildInputs = with pkgs.buildPackages; [ bash ];

                buildInputs = with crossPkgsStatic; [
                  libxcrypt
                  zlib
                  openssl
                ];

                hardeningDisable = [ "fortify" ];

                preConfigure = ''
                  patchShebangs scripts/
                '';

                configurePhase = ''
                  runHook preConfigure
                  # Export CC to point to the cross-compiler
                  export HOSTCC=${pkgs.buildPackages.gcc}/bin/gcc
                  make defconfig
                  runHook postConfigure
                '';

                makeFlags = [ "LDFLAGS=--static" ];

                buildPhase = ''
                  runHook preBuild
                  make $makeFlags toybox
                  runHook postBuild
                '';

                installPhase = ''
                  runHook preInstall
                  mkdir -p $out/bin
                  cp toybox $out/bin/toybox
                  runHook postInstall
                '';

                meta = with pkgs.lib; {
                  description = "Toybox for ${targetSystem}";
                  homepage = "http://landley.net/toybox";
                  license = licenses.bsd0;
                  platforms = platforms.linux;
                };
              };

              # Cross-compiled single command
              mkCrossSingleCommand =
                command:
                crossPkgsStatic.stdenv.mkDerivation {
                  pname = "toybox-${command}-${targetSystem}";
                  version = "0.8.11";

                  src = toybox;

                  depsBuildBuild = with pkgs.buildPackages; [
                    bash
                    gcc
                  ];
                  nativeBuildInputs = with pkgs.buildPackages; [ bash ];

                  buildInputs = with crossPkgsStatic; [
                    libxcrypt
                    zlib
                    openssl
                  ];

                  hardeningDisable = [ "fortify" ];

                  preConfigure = ''
                    patchShebangs scripts/
                    # Export HOSTCC for build scripts
                    export HOSTCC=${pkgs.buildPackages.gcc}/bin/gcc
                  '';

                  makeFlags = [ "LDFLAGS=--static" ];

                  buildPhase = ''
                    runHook preBuild
                    make $makeFlags ${command}
                    runHook postBuild
                  '';

                  installPhase = ''
                    runHook preInstall
                    mkdir -p $out/bin
                    cp ${command} $out/bin/${command}
                    runHook postInstall
                  '';

                  meta = with pkgs.lib; {
                    description = "Toybox ${command} for ${targetSystem}";
                    homepage = "http://landley.net/toybox";
                    license = licenses.bsd0;
                    platforms = platforms.linux;
                  };
                };

              # Create cross command packages
              crossCommandPackages = builtins.listToAttrs (
                map (cmd: {
                  name = "${cmd}-${targetSystem}";
                  value = mkCrossSingleCommand cmd;
                }) commands
              );
            in
            crossCommandPackages
            // {
              "toybox-${targetSystem}" = crossToyboxBase;
            };

          # Create cross-compilation packages for all targets
          allCrossPackages = pkgs.lib.foldl' (acc: target: acc // (mkCrossPackages target)) { } crossTargets;

        in
        # Merge native and cross-compiled packages
        commandPackages
        // {
          default = toyboxBase;
          toybox = toyboxBase;
        }
        // allCrossPackages
      );
    };
}
