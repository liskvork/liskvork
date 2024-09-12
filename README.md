# liskvork

Modern multi-platform piskvork reimplementation.

Linux, Windows and MacOS support (with priority to Linux) on both x86_64 and
aarch64.

## Building from source

### Docker

```sh
VERSION=1.0.0 docker build . --build-arg BUILD_VERSION=${VERSION} -t liskvork:${VERSION}
```

### No docker

#### Dependencies

- zig 0.13.0 (May work with newer versions but has not been tested)

#### Step

```sh
zig build -Doptimize=ReleaseSafe
```

## Installing

TBD

## Launching liskvork

### System package

Just launch liskvork like this:

```sh
liskvork
```

### From source build

```sh
# From the root of the repository once built
./zig-out/bin/liskvork
```

### Docker

```sh
# Once compiled with docker
VERSION=1.0.0 docker run liskvork:${VERSION}
```

## Configuration

TBD
