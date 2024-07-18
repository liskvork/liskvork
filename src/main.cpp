#include <cstdlib>
#include <iostream>

#ifdef UNIT_TESTS
#define MAIN definitely_not_main
#else
#define MAIN main
#endif

auto MAIN() -> int
{
    std::cout << "Hello, World!" << std::endl;
    return EXIT_SUCCESS;
}
