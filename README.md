# liskvork

Linux native piskvork reimplementation for Epitech students.

It should also support Mac (Intel and Apple Silicon) but if there are problems
please open an issue
[here](https://github.com/Epitech/B-AIA-500_liskvork/issues).

## Building from source

### Docker

TBD

### No docker

#### Dependencies

- gcc7* (Any c++17 compliant compiler should work but it is not guarranted as we do not code strictly to the standard)
- gnumake (Build system, other make versions might work but have not been tested)

\* gcc7 is the lowest version that should work with this codebase but it has not been tested yet, a higher compiler version will always be recommended for optimization reasons. See the gcc c++17 feature matrix
[here](https://gcc.gnu.org/projects/cxx-status.html#cxx17).

#### Step

```sh
make -j `nproc --exclude 1` # The -j option is here to speed-up the compilation
```

## Installing

TBD

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
liskvork
```

### From source build

```sh
# From the root of the repository once built
./liskvork
```

### Docker

TBD

## Configuration

TBD
