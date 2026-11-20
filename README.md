# sylvan

sylvan turns a directory tree into a flake. Put a host in `hosts/`, modules in `modules/`, packages in `packages/`, and sylvan builds `nixosConfigurations`, `darwinConfigurations`, and `packages.<system>` from them.

```nix
{
  inputs.sylvan.url = "github:z1-0/sylvan";

  outputs = inputs: inputs.sylvan inputs ./.;
}
```

That is the whole flake; the rest is files on disk.

## Features

- `hosts/laptop/` becomes `nixosConfigurations.laptop`, and the platform comes from the host's own modules.
- `modules/shared` applies to every host, `modules/nixos` and `modules/darwin` only to their own platform.
- Every entry in `users.users` gets a home-manager config that imports `modules/home/users/<name>/`.
- `_meta` in a module file is extracted at AST level, stripped before evaluation, and exposed as `inputs.self.lib.metaModules`, with no registry file to keep in sync.
- Hostname, `system.stateVersion`, and `home.stateVersion` come from defaults, so you do not write them in each host file.
- `flake/` is imported as flake-parts modules, so any option sylvan does not cover stays reachable.

## Requirements

- Nix with flakes enabled.
- The `nixpkgs` input. `nix-darwin` and `home-manager` are optional: without `nix-darwin` sylvan drops darwin hosts, and without `home-manager` it attaches no home-manager modules.

## Quick start

### 1. Declare the inputs

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
    sylvan.url = "github:z1-0/sylvan";
  };

  outputs = inputs: inputs.sylvan inputs ./.;
}
```

> [!NOTE]
> The functor ignores its first argument, so `inputs.sylvan inputs ./.` and the example flake's `_._ _ ./.` are the same call: sylvan receives the whole input set plus the directory to load.

### 2. Describe a host

```nix
# hosts/laptop/default.nix
{ ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
```

### 3. Add modules

```nix
# modules/shared/ssh.nix
{ ... }:
{
  services.openssh.enable = true;
}

# modules/nixos/boot.nix
{ ... }:
{
  boot.loader.systemd-boot.enable = true;
}

# modules/home/users/alice/git.nix
{ ... }:
{
  programs.git.settings.user.name = "Alice";
}
```

### 4. Build

```bash
nixos-rebuild switch --flake .#laptop
darwin-rebuild switch --flake .#imac
```

## Project layout

```
.
├── flake.nix
├── hosts/
│   ├── laptop/default.nix       → nixosConfigurations.laptop
│   └── imac/default.nix         → darwinConfigurations.imac
├── modules/
│   ├── shared/                  every host
│   ├── nixos/                   NixOS hosts only
│   ├── darwin/                  darwin hosts only
│   └── home/
│       ├── shared/              every user's home-manager config
│       └── users/alice/         alice's home-manager config
├── packages/                     packages.<system>.<name>
├── overlays/                     overlays.<name>
└── flake/                        flake-parts modules
```

| Path | How it is consumed |
| --- | --- |
| `hosts/<name>/` or `hosts/<name>.nix` | Host modules; every `.nix` file under the host is collected |
| `modules/shared/` | Added to every host's module list |
| `modules/nixos/`, `modules/darwin/` | Added only for that kernel |
| `modules/home/shared/` | `sharedModules` for every home-manager user |
| `modules/home/users/<user>/` | `imports` for that user's home-manager config |
| `packages/*.nix` | Through `pkgs.callPackage` when the file evaluates to a function |
| `overlays/*.nix` | Exposed as flake `overlays.<name>` |
| `flake/` | Imported into flake-parts |

All directories are optional. Only `.nix` files are read; `packages/` and `overlays/` must be flat, while `hosts/`, `modules/`, and `flake/` can nest.

## How a host is assembled

1. sylvan evaluates the host's modules in a probe pass with relaxed checking, reads `nixpkgs.hostPlatform` (or the legacy `nixpkgs.system`), and collects the names in `users.users`.
2. sylvan resolves the platform with `lib.systems.elaborate`, which also accepts ABI-suffixed values such as `x86_64-linux-gnu`. Linux routes to `nixosSystem`, darwin to `darwinSystem`.
3. The module list runs in this order: the host's modules, the `networking.hostName` default, the `system.stateVersion` default, `modules/shared`, the platform modules, then the home-manager block.
4. Every discovered user gets a home-manager configuration with `useGlobalPkgs`, `useUserPackages`, the shared home modules, and that user's own directory.
5. `flake/` modules are imported, so extra flake-parts options and outputs keep working.

> [!TIP]
> `networking.hostName` defaults to the host directory name, and `system.stateVersion` follows the platform's current release. Both are `mkDefault`, so set them explicitly when you need to pin a release.

sylvan skips a host it cannot build and warns with the reason: no platform set, a failed evaluation, a non-string platform, or a kernel other than Linux or darwin.

## Metadata

Any module file may declare a top-level `_meta` attribute set:

```nix
# modules/nixos/network.nix
{ ... }:
{
  _meta = {
    description = "NetworkManager and firewall defaults";
    tags = [ "network" ];
  };

  networking.networkmanager.enable = true;
}
```

sylvan parses the file's AST, removes `_meta`, and re-imports the stripped copy, so the module never sees the attribute and strict modules keep working. The extracted values are grouped by area, and every host system can read them:

```nix
# modules/nixos/audit.nix
{ inputs, ... }:
{
  environment.etc."module-audit".text =
    inputs.self.lib.metaModules.nixos.network.meta.description;
}
```

`lib.metaModulesFor pkgs` builds that tree for any system, and `lib.rootTree` holds the loaded source tree.

> [!WARNING]
> Metadata extraction runs the parser/renderer through import-from-derivation, so the evaluating machine needs a working Nix build.

## Overlays

sylvan exposes each file in `overlays/` as `overlays.<name>`. When a file takes `{ inputs }`, sylvan applies the flake input set first:

```nix
# overlays/tools.nix
{ inputs }: final: prev: {
  # `inputs` is your flake input set (nixpkgs, home-manager, ...)
  myTools = prev.symlinkJoin {
    name = "my-tools";
    paths = [ prev.hello prev.jq ];
  };
}
```

A plain `final: prev: ...` overlay needs no wrapper and passes through unchanged.

sylvan does not add these overlays to host `pkgs`. To apply one, add it to `nixpkgs.overlays` in a module:

```nix
{ inputs, ... }:
{
  nixpkgs.overlays = [ inputs.self.overlays.tools ];
}
```

## Packages

sylvan evaluates `packages/` once per system and passes each file through `pkgs.callPackage` when the file evaluates to a function:

```nix
# packages/hello.nix
{ pkgs, ... }:
pkgs.writeShellScriptBin "hello" "printf 'hello\n'"
```

```bash
nix build .#hello
```

## Flake outputs

| Output | Contents |
| --- | --- |
| `nixosConfigurations.<host>` | Every Linux host |
| `darwinConfigurations.<host>` | Every darwin host, when `nix-darwin` is an input |
| `packages.<system>.<name>` | From `packages/` |
| `overlays.<name>` | From `overlays/` |
| `lib.rootTree` | Loaded source tree with node names, paths, and contents |
| `lib.metaModulesFor` | `pkgs -> metadata tree` |
| anything else | Contributed by `flake/` modules |

`systems` covers `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`, plus every platform a discovered host asks for.

## Related projects

- [srctree-nix](https://github.com/z1-0/srctree-nix): filesystem trees and their algorithms.
- [metatree-nix](https://github.com/z1-0/metatree-nix): `_meta` extraction on top of srctree.
- [flake-parts](https://github.com/hercules-ci/flake-parts): the flake framework sylvan builds on.
