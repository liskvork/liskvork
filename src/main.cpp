#include <iostream>

#ifdef UNIT_TESTS
#define MAIN not_main
#else
#define MAIN main
#endif

int MAIN(int argc, const char **argv)
{
    std::cout << "Hello, World" << std::endl;
    return 0;
}
