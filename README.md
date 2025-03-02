# liskvork

Modern multi-platform gomoku game server.

Linux, Windows and MacOS support (with priority to Linux) on both x86_64 and
aarch64.

Main repository URL: <https://github.com/liskvork/liskvork>

## Reporting bugs/Submitting patches

You can see open tickets and report bugs over
[here](https://github.com/liskvork/liskvork/issues).

You can submit patches/PRs over
[here](https://github.com/liskvork/liskvork/pulls).

## Building from source

### Docker

```sh
docker build . --build-arg BUILD_VERSION=0.0.0-dev -t liskvork
```

### No docker

#### Dependencies

- zig 0.13.0 (May work with newer versions but has not been tested)

#### Step

```sh
zig build -Doptimize=ReleaseSafe
```

## Installing

Get the binary from
[Github release tab](https://github.com/liskvork/liskvork/releases) and then
just launch it.

## Launching liskvork

### From source build

```sh
# From the root of the repository once built
./zig-out/bin/liskvork
```

### Docker

```sh
# Once compiled with docker
docker run -v $(pwd):/data/:Z liskvork
```

### Nix

This method might be broken as it is not maintained anymore.

```sh
# On a system with nix installed and flakes activated
nix run github:liskvork/liskvork
```

## Configuration

Look at the default `config.ini` that's created when launching for the first
time everything (should) be documented properly to configure it.
