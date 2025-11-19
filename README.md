# nix-toybox-static

A Nix flake for building statically-linked [Toybox](http://landley.net/toybox/)
binaries with musl-libc, supporting native and cross-compilation to all
architectures.

## Features

- **Static binaries**: All binaries are statically linked with musl-libc for
  maximum portability
- **Cross-compilation**: Build for any Linux architecture from any system
- **Individual commands**: Build standalone binaries for specific commands
  (e.g., just `sed` or `grep`)
- **Full toybox**: Build the complete multicall binary with all commands
- **Automatic discovery**: Commands are automatically discovered from the toybox
  source
- **No maintenance**: Uses nixpkgs' built-in system lists - automatically
  supports new architectures

## Quick Start

### Build full toybox for your system

```bash
nix build github:pinpox/nix-toybox-static
./result/bin/toybox
```

### Build individual commands

```bash
nix build github:pinpox/nix-toybox-static#sed
nix build github:pinpox/nix-toybox-static#grep
nix build github:pinpox/nix-toybox-static#ls
```

## Cross-Compilation

Build for any architecture from any system:

Use `pkgsCross.<curent architecture>.<target architecture>.<command>` to
cross-compile from `<current archicecture>` to `<target architecture>`.

For example to build `mkdir` for `aarch64-darwin` on a `x86_64-linux` system
use:

```bash
nix build .\#pkgsCross.x86_64-darwin.aarch64-darwin.acpi
```
Run `nix flake show` to see all available packages.

## Available Commands

The flake includes 200+ commands from toybox, automatically discovered from the source:

- **File utilities**: `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `find`, `tar`, `cpio`
- **Text processing**: `sed`, `grep`, `awk`, `cut`, `sort`, `uniq`, `wc`, `head`, `tail`
- **System utilities**: `ps`, `top`, `kill`, `free`, `df`, `mount`, `dmesg`
- **Network tools**: `wget`, `ping`, `netcat`, `ifconfig`, `netstat`
- **And many more**: Run `nix flake show` to see all available commands

## Upstream

- Toybox project: https://landley.net/toybox/
- Toybox source: https://github.com/landley/toybox
