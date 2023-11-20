# liskvork

Linux native piskvork reimplementation for Epitech students.

It should also support Mac (Intel and Apple Silicon) but if there are problems
please open an issue [here](https://gitlab.com/huntears/liskvork/-/issues).

## Building from source

### Docker

```sh
$ docker build . -t liskvork:latest-local
```

### No docker

#### Dependencies

Some other dependencies are most likely needed, but I am not sure which

 - gcc-12+ or clang-15+

#### Steps

```sh
$ mkdir build
$ cd build
$ cmake -DCMAKE_BUILD_TYPE=Release ..
$ cmake --build . --jobs `nproc`
```

If that doesn't work you might be missing dependencies and you should open an
issue [here](https://gitlab.com/huntears/liskvork/-/issues) so I can add it to
the list, or even better you can open an MR
[here](https://gitlab.com/huntears/liskvork/-/merge_requests) to add it
yourself :).

## Installing


You can download an RPM or DEB package from the
[release tab](https://gitlab.com/huntears/liskvork/-/releases) and just install
it with one of the following command:

```sh
$ sudo apt install ./liskvork-*.deb
$ sudo dnf install ./liskvork-*.rpm
```

You also have a static binary available that should normally work on any Linux
distribution (Not on MAC from what I have observed already).

### Non x86 systems

You currently need to build from source if you want to use liskvork on a non
x86 system, as I currently do not have access to any servers to build liskvork
other than x86.

If you want ARM (Or even RISC-V) builds to happen then I would gladly accept
any access to a server with those architectures to maintain liskvork.

## Launching liskvork

### System package

Just launch liskvork like this:

```sh
$ liskvork
```

A config file will be generated and you can modify it as you need

### From source build

Launch liskvork from inside the `build/bin` directory:

```sh
# From the root of the repository once built
$ cd build/bin
$ ./liskvork
```

A config file will be generated and you can modify it as you need

### Docker

Provided that you have built the docker image locally (There is no publicly
available docker image yet) you can use that command:

```sh
# If you want this example to work you need two player binaries in the cwd
# called player1 and player2
$ docker run \
    -v $(pwd):/usr/app/data \
    -e LV_HEADLESS=true \
    -e LV_PLAYER1_EXE=/usr/app/data/player1 \
    -e LV_PLAYER2_EXE=/usr/app/data/player2 \
    liskvork:latest-local
```

This command will launch liskvork in headless mode with 2 players (player1 and
player2). This will all be launched inside a docker container running an
official stripped down version of fedora 38.

Tips: Create a docker-compose.yml if you are going to launch that command a lot
;)

## Configuration

There are multiple ways to configure liskvork, here they are with the priority
in which they are taken:

Command line arguments -> Environment variables -> Config file

### Configuration options

| CLI | Env | YML | Notes |
| --- | --- | --- | ----- |
| --headless | LV_HEADLESS | general.headless | Terminal only (No GUI) |
| --debug-enable | LV_DEBUG_ENABLE | debug.enable | Debug logs |
| --debug-board | LV_DEBUG_BOARD | debug.board | Display board after each move (Depends on --debug-enable) |
| --player1-exe | LV_PLAYER1_EXE | player1.exe | Path to player1's executable |
| --player1-limits-memory | LV_PLAYER1_LIMITS_MEMORY | player1.limits.memory | Maximum allowed memory for player1 in bytes (Setting that value too low can cause crashed in liskvork!) |
| --player1-limits-time | LV_PLAYER1_LIMITS_TIME | player1.limits.time | Maximum allowed time per turn for player1 in milliseconds |
| --player2-exe | LV_PLAYER2_EXE | player2.exe | Path to player2's executable |
| --player2-limits-memory | LV_PLAYER2_LIMITS_MEMORY | player2.limits.memory | Maximum allowed memory for player2 in bytes (Setting that value too low can cause crashed in liskvork!) |
| --player2-limits-time | LV_PLAYER2_LIMITS_TIME | player2.limits.time | Maximum allowed time per turn for player2 in milliseconds |

## Notes

Some things have a very specific implementation, here they are:

 - Match timeout has not been implemented yet
 - Turn timeout only takes into effect after the player played (The manager can
  effectively be soft-locked if a player doesn't answer anything)
 - Tie has not been implemented yet (It is for now completely undefined
  behaviour)

But some features have been added to help in creating the best ai possible:

 - When a player wins the manager will exit with a specific exit code (e.g.
  player1 wins then the manager will exit with 1).
 - When the manager has an error it will display it (or not uwu) and then exit
  with status code 3.
