# Building srcML with Nix

This repo ships a `flake.nix` that gives you a reproducible build environment via Nix. This document explains both how to use it and how flakes work, so you can adapt it later.

## Quick start

```bash
# enter a shell with all build deps available
nix develop

# inside the shell, build as usual
cmake -S . -B build -G Ninja -DBUILD_CLIENT_TESTS=OFF -DBUILD_LIBSRCML_TESTS=ON
cmake --build build
ctest --test-dir build -R convenience --output-on-failure

# or one-shot a command without entering the shell
nix develop -c cmake -S . -B build -G Ninja
nix develop -c cmake --build build

# attempt a full reproducible build
nix build .#default
```

The first `nix develop` will pin everything into `flake.lock` — commit that file so collaborators (and CI) get the exact same toolchain. Update later with `nix flake update`.

## Alternative: `build.sh` one-liner (no flake)

For a simpler, channel-based approach (less reproducible, no lock file), the repo also ships a `build.sh`:

```bash
./build.sh                       # build everything
./build.sh srcml                 # build just the CLI
./build.sh test_srcml_convenience
```

The shebang `#!/usr/bin/env nix-shell` + `#!nix-shell -i bash -p ...` tells Nix: "spin up a shell with these packages on PATH, then run this script with bash inside it." First run downloads the packages into `/nix/store`; subsequent runs are instant (cached).

---

## How flakes work — the mental model

### 1. A flake is a self-contained `flake.nix` + `flake.lock`

- `flake.nix` declares **inputs** (what dependencies look like) and **outputs** (what you export — packages, dev shells, NixOS modules, apps).
- `flake.lock` is auto-generated and pins each input to a specific git revision and content hash. Anyone running your flake gets bit-identical inputs.

### 2. The structure is always

```nix
{
  inputs  = { ... };                  # external dependencies
  outputs = inputs: { ... };          # pure function: inputs -> attrs
}
```

The `outputs` function takes a record of resolved inputs and returns an attrset. Nix knows certain names — `packages.<system>.default`, `devShells.<system>.default`, `apps.<system>.default`, `nixosConfigurations.<host>`, `formatter.<system>` — and the CLI exposes them via `nix build`, `nix develop`, etc.

### 3. `flake-utils.eachDefaultSystem`

Sugar that wraps the body so you don't have to repeat `x86_64-linux`, `aarch64-darwin`, etc. for every output. Without it you'd write `packages.x86_64-linux.default = ...; packages.aarch64-darwin.default = ...;` by hand.

### 4. `pkgs = nixpkgs.legacyPackages.${system}`

Gives you the conventional `pkgs.cmake`, `pkgs.curl` namespace. It's called `legacyPackages` because the flake-native `packages` attribute is a stricter, smaller set; `legacyPackages` is the full nixpkgs tree.

### 5. Two outputs in this flake

**`devShells.default`** → `nix develop` drops you into a bash shell where `nativeBuildInputs` and `buildInputs` are on `PATH`, `CMAKE_PREFIX_PATH`, `PKG_CONFIG_PATH`, etc. *No build runs.* You then run cmake/ninja yourself. This is the "interactive" mode.

- `nativeBuildInputs` = tools that run on the build host (compilers, cmake, jdk for ANTLR).
- `buildInputs` = libraries the resulting binary links against (libxml2, libcurl).
- On cross-compilation the distinction matters; on a single-host build they're functionally similar but the convention pays off later.

**`packages.default`** → `nix build` runs an actual sandboxed build that produces a `result/` symlink in the cwd pointing into `/nix/store`. This is the "ship a binary" mode. Marked `__noChroot = true` in our flake because srcML's cmake fetches a manpage and ANTLR sources at configure time — network access is forbidden in the default sandbox, so we either turn the sandbox off (`__noChroot`) or fix the build to not fetch (better long-term).

### 6. The pin (`flake.lock`)

When you first run anything, Nix fetches `nixos-24.05` from GitHub, computes its hash, and writes both into `flake.lock`. Next run uses the lock. `nix flake update` re-resolves and rewrites the lock. This is the difference vs. channels: channels are mutable per-machine state; flakes are version-controlled per-project.

### 7. Pure evaluation

Flake outputs are evaluated *purely* — no `import <nixpkgs>`, no `builtins.getEnv`, no reading random files. Everything must come through `inputs`. That's what makes flakes reproducible.

---

## How Nix packages work — the bigger picture

- **Everything lives under `/nix/store/<hash>-<name>/`.** The hash is computed from *all* inputs (sources, dependencies, build flags). Change any input → different hash → different store path. Nothing global, nothing in `/usr/lib`.
- A **derivation** is the recipe: "given these inputs, run this build script, produce these outputs." Building a derivation is pure: same inputs → same outputs, cached forever.
- **`nixpkgs`** is a giant set of derivations. You reference them as `pkgs.curl`, `pkgs.cmake`, etc.
- **`nix-shell` / `nix shell` / `nix develop`** drop you into an environment where the requested derivations' `bin/`, `include/`, `lib/` are on `PATH` / `CMAKE_PREFIX_PATH` / `PKG_CONFIG_PATH`. CMake's `find_package` then just works — that's why CMake errors like `Could NOT find CURL` go away once curl is in the shell.
- **Two interfaces** in the wild:
  - **Channels** (older): `<nixpkgs>` resolves to whatever your `nix-channel` last fetched. Mutable, depends on machine state.
  - **Flakes** (newer): `flake.nix` pins inputs in `flake.lock` (a content-hashed reference). Reproducible across machines.

---

## Updating Nix itself

**Channels (classic, `nix-env`/`nix-shell`):**
```bash
nix-channel --update              # user channels
sudo nix-channel --update         # root channels (if you installed packages as root)
nix-channel --list                # see what's configured
```

**NixOS:**
```bash
sudo nix-channel --update
sudo nixos-rebuild switch
```

**Home Manager:**
```bash
nix-channel --update
home-manager switch
```

**Flakes:**
```bash
cd /path/to/flake                 # directory with flake.nix
nix flake update                  # bump all inputs in flake.lock
nix flake update nixpkgs          # bump just one input
sudo nixos-rebuild switch --flake .#hostname    # apply NixOS
home-manager switch --flake .                   # apply Home Manager
```

**One-shot up-to-date dev shell without touching your system:**
```bash
nix-shell -I nixpkgs=channel:nixos-unstable -p curl libxml2 libxslt libarchive cmake ninja
# or with flakes:
nix shell nixpkgs#curl nixpkgs#libxml2 nixpkgs#libxslt nixpkgs#libarchive nixpkgs#cmake nixpkgs#ninja
```

---

## Command reference

| Command | What it does |
|---|---|
| `nix develop` | Enter the default devShell |
| `nix develop -c <cmd>` | Run one command inside the devShell |
| `nix build` | Build `packages.default`, symlink to `./result` |
| `nix run` | Build `apps.default` (or `packages.default`) and execute it |
| `nix flake update` | Bump all inputs in `flake.lock` |
| `nix flake update nixpkgs` | Bump just one input |
| `nix flake show` | List all outputs of the flake |
| `nix flake check` | Evaluate every output (catches bitrot) |
| `nix-shell -p <pkgs>` | Ad-hoc shell with packages from current channel |
| `nix shell nixpkgs#<pkg>` | Ad-hoc shell with packages from a flake input |

---

## Troubleshooting

**`Could NOT find CURL` / `LibArchive` / etc.** — CMake's `find_package` is looking in system locations that don't exist on Nix. Fix by either (a) adding the lib to `buildInputs` in `flake.nix` so it's on `CMAKE_PREFIX_PATH`, or (b) passing `-DCURL_INCLUDE_DIR=... -DCURL_LIBRARY=...` explicitly.

**`nix build` fails with sandbox errors about network access.** — The build is reaching out to fetch something. Either fix the build to not fetch at configure time, or set `__noChroot = true` on the derivation (escape hatch — disables the sandbox for that derivation only).

**Different machines get different builds.** — You forgot to commit `flake.lock`. Without the lock, `nix develop` re-resolves inputs from `nixpkgs/nixos-24.05` HEAD each time.

**`error: experimental Nix feature 'flakes' is disabled`.** — Add to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`):
```
experimental-features = nix-command flakes
```
