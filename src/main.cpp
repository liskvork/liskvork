#include <iostream>

#include "configuration/ConfigHandler.hpp"
#include "logging/logging.hpp"

#ifdef UNIT_TESTS
#define MAIN not_main
#else
#define MAIN main
#endif

static auto initArgs(int argc, const char **argv)
{
    auto program = configuration::ConfigHandler(PROGRAM_NAME, PROGRAM_VERSION);

    // clang-format off
    program.add("headless")
        .help("No preview window opens")
        .valueFromArgument("--headless")
        .valueFromEnvironmentVariable("LV_HEADLESS")
        .possibleValues(true, false)
        .defaultValue(true)
        .implicit();
    // clang-format on

    try {
        program.load("./config.yml");
    } catch (const configuration::BadFile &) {
        if (std::filesystem::exists("./config.yml")) {
            LERROR("Failed to open config file, check permissions");
            std::exit(1);
        }
        LWARN("No config file found, creating one");
        program.save("./config.yml");
    }

    try {
        program.parse(argc, argv);
    } catch (const std::runtime_error &err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program;
        std::exit(1);
    }

    return program;
}

int MAIN(int argc, const char **argv)
{
    auto program = initArgs(argc, argv);
    return 0;
}
