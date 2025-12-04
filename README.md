# liskvork

Modern multi-platform gomoku game server.

Main repository URL: <https://git.sr.ht/~emneo/liskvork>

[![builds.sr.ht status](https://builds.sr.ht/~emneo/liskvork.svg)](https://builds.sr.ht/~emneo/liskvork)

## Contribution

Please take a look at the [CONTRIBUTING.md](CONTRIBUTING.md) file, then consider
sending a patch on the
[development mailing list](https://lists.sr.ht/~emneo/liskvork-devel).

## License

liskvork is licensed under the
[European Union Public License 1.2](https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12)
or later.

## Support

|         | x86-64 | aarch64 | riscv64 |
|---------|--------|---------|---------|
| Linux   | 🟢     | 🟡      | 🟡      |
| Windows | 🟡     | 🟡      | 🔴      |
| MacOS   | 🟡     | 🟡      | 🔴      |
| FreeBSD | 🟡     | 🟡      | 🟡      |
| NetBSD  | 🟡     | 🟡      | 🔴      |
| OpenBSD | 🔴     | 🔴      | 🔴      |

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

- zig 0.15.0 (May work with newer versions but has not been tested)

#### Step

```sh
zig build -Doptimize=ReleaseSafe
```

## Installing

### Arch Linux (AUR)

[liskvork](https://aur.archlinux.org/packages/liskvork) is available as a package in the [AUR](https://aur.archlinux.org). You can install it with your preferred [AUR helper](https://wiki.archlinux.org/title/AUR_helpers). For example `paru`:
```bash
paru -S liskvork
```

### Other OS & Linux Distributions

You can download the binaries [straight from the official release page](https://releases.liskvork.org) and add them to a directory specified in your `PATH` environment. Make sure to download the right release for your OS and architecture.

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

Look at the default `config.ini` that's created when launching with the `--init-config` flag. 
Everything (should) be documented properly to configure it.

If you wish to reset the configuration, just run liskvork with the `--init-config` flag once again.

Some configuration values can be overriden at runtime with flags. Please consult `liskvork --help` for more information.

You can also use a different config file with the `-c` flag, followed with the path to the configuration file.
