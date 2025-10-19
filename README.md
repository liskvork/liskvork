# liskvork

Modern multi-platform gomoku game server.

Main repository URL: <https://git.sr.ht/~emneo/liskvork>

<!-- [![CI](https://github.com/liskvork/liskvork/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/liskvork/liskvork/actions/workflows/CI.yml) -->

## Contribution

Please take a look at the [CONTRIBUTING.md](CONTRIBUTING.md) file, then consider
sending a patch on the
[development mailing list](https://lists.sr.ht/~emneo/liskvork-devel).

## License

liskvork is licensed under the
[European Union Public License 1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)
or later.

## Support

|              | x86-64 | aarch64 |
|--------------|--------|---------|
| Linux (GNU)  | 🟢     | 🟡      |
| Linux (MUSL) | 🟢     | 🟡      |
| Windows      | 🟡     | 🟡      |
| MacOS        | 🟡     | 🟡      |
| OpenBSD      | 🔴     | 🔴      |
| FreeBSD      | 🔴     | 🔴      |

🟢 - Supported and actively tested

🟡 - Supported but not actively tested

🔴 - Not supported

## Reporting bugs/Submitting patches

You can see open tickets bugs over
[here](https://todo.sr.ht/~emneo/liskvork).

You can submit patches over
[here](https://lists.sr.ht/~emneo/liskvork-devel).

You can talk/discuss about the project, and ask questions about it over
[here](https://lists.sr.ht/~emneo/liskvork-discuss).

## Building from source

### Docker

```sh
docker build . --build-arg BUILD_VERSION=0.0.0-dev -t liskvork
```

### No docker

#### Dependencies

- zig 0.14.0 (May work with newer versions but has not been tested)

#### Step

```sh
zig build -Doptimize=ReleaseSafe
```

## Installing

<!-- Get the binary from
[Github release tab](https://github.com/liskvork/liskvork/releases) and then
just launch it. -->

Currently no binaries are available. TBD.

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

```sh
nix --extra-experimental-features "nix-command flakes" \
  run sourcehut:~emneo/liskvork
```

## Configuration

Look at the default `config.ini` that's created when launching for the first
time everything (should) be documented properly to configure it.
