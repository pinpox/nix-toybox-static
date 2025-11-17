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

### Build for x86_64 (from any system)

```bash
nix build github:pinpox/nix-toybox-static#toybox-musl64
nix build github:pinpox/nix-toybox-static#sed-musl64
```

### Build for ARM64 (from any system)

```bash
nix build github:pinpox/nix-toybox-static#toybox-aarch64-multiplatform
nix build github:pinpox/nix-toybox-static#ls-aarch64-multiplatform
```

### Build for RISC-V (from any system)

```bash
nix build github:pinpox/nix-toybox-static#toybox-riscv64
nix build github:pinpox/nix-toybox-static#grep-riscv64
```

## Available Architectures

The flake automatically supports all Linux cross-compilation targets from nixpkgs, including:

- **x86**: `musl64` (x86_64), `musl32` (i686)
- **ARM**: `aarch64-multiplatform`, `armv7l-hf-multiplatform`
- **RISC-V**: `riscv64`, `riscv64-musl`
- **PowerPC**: `ppc64`, `ppc64-musl`
- **MIPS**: `mips64-linux-gnuabi64`, `mips64el-linux-gnuabi64`
- **Others**: `loongarch64-linux`, `s390x`

And many more! Run `nix flake show` to see all available packages.

## Usage in Your Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-toybox-static.url = "github:pinpox/nix-toybox-static";
  };

  outputs = { self, nixpkgs, nix-toybox-static }: {
    # Use in your packages
    packages.x86_64-linux.myPackage = nixpkgs.legacyPackages.x86_64-linux.stdenv.mkDerivation {
      name = "my-package";
      buildInputs = [
        nix-toybox-static.packages.x86_64-linux.sed
        nix-toybox-static.packages.x86_64-linux.grep
      ];
    };
  };
}
```

## Available Commands

The flake includes 200+ commands from toybox, automatically discovered from the source:

- **File utilities**: `cat`, `ls`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `find`, `tar`, `cpio`
- **Text processing**: `sed`, `grep`, `awk`, `cut`, `sort`, `uniq`, `wc`, `head`, `tail`
- **System utilities**: `ps`, `top`, `kill`, `free`, `df`, `mount`, `dmesg`
- **Network tools**: `wget`, `ping`, `netcat`, `ifconfig`, `netstat`
- **And many more**: Run `nix flake show` to see all available commands

## Examples

### Portable static binary

```bash
# Build a static grep for x86_64
nix build github:pinpox/nix-toybox-static#grep-musl64

# Copy to any x86_64 Linux system and run
scp result/bin/grep remote-host:
ssh remote-host ./grep --version
```

### Cross-compile for embedded ARM device

```bash
# From your x86_64 laptop, build for ARM
nix build github:pinpox/nix-toybox-static#toybox-armv7l-hf-multiplatform

# Deploy to Raspberry Pi or similar
scp result/bin/toybox pi@raspberry:
ssh pi@raspberry ./toybox ls -la
```

### Verify static linking

```bash
nix build github:pinpox/nix-toybox-static#ls
file result/bin/ls
# Output: ELF 64-bit LSB executable, x86-64, statically linked, stripped

ldd result/bin/ls
# Output: not a dynamic executable
```

## Upstream

- Toybox project: https://landley.net/toybox/
- Toybox source: https://github.com/landley/toybox
