# liskvork

[![builds.sr.ht status](https://builds.sr.ht/~emneo/liskvork.svg)](https://builds.sr.ht/~emneo/liskvork)

Modern multi-platform gomoku game server.

Linux, Windows and MacOS support (with priority to Linux) on both x86_64 and
aarch64.

Main repository URL: <https://git.sr.ht/~emneo/liskvork>

## Reporting bugs/Submitting patches

You can see open tickets over at [here](https://todo.sr.ht/~emneo/liskvork).

You can submit bug reports and patches over at the
[mailing lists](https://sr.ht/~emneo/liskvork/lists)
(yes that means sending a mail, it is not hard.)

The ticket board is only opened to maintainers, so if you need to report a bug
do it on the mailing lists, if the bug report is accepted it will be listed in
the ticket board.

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

Get the binary from https://releases.liskvork.org and then just launch it.

## Launching liskvork

### From source build

```sh
# From the root of the repository once built
./zig-out/bin/liskvork
```

### Docker

```sh
# Once compiled with docker
docker run liskvork
```

## Configuration

Look at the default `config.ini` that's created when launching for the first
time everything (should) be documented properly to configure it.
