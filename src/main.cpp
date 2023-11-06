#include <csignal>
#include <exception>
#include <iostream>
#include <limits>
#include <optional>

#include "Player.hpp"
#include "configuration/ConfigHandler.hpp"
#include "liskvork.hpp"
#include "logging/Registry.hpp"
#include "logging/logging.hpp"
#include "options.hpp"

#ifdef UNIT_TESTS
#define MAIN not_main
#else
#define MAIN main
#endif

namespace {

std::optional<configuration::ConfigHandler> initArgs(int argc, const char **argv)
{
    std::optional<configuration::ConfigHandler> program = configuration::ConfigHandler(PROGRAM_NAME, PROGRAM_VERSION);

    // clang-format off
    program->add("headless")
        .help("No preview window opens")
        .valueFromConfig("general", "headless")
        .valueFromArgument("--headless")
        .valueFromEnvironmentVariable("LV_HEADLESS")
        .possibleValues(true, false)
        .defaultValue(true)
        .implicit();

    program->add("player1-exe")
        .help("Path to the executable for player1")
        .valueFromConfig("player1", "exe")
        .valueFromArgument("--player1-exe")
        .valueFromEnvironmentVariable("LV_PLAYER1_EXE")
        .defaultValue("player1");

    program->add("player1-limits-memory")
        .help("Memory limit for player1 in bytes")
        .valueFromConfig("player1", "limits", "memory")
        .valueFromArgument("--player1-limits-memory")
        .valueFromEnvironmentVariable("LV_PLAYER1_LIMITS_MEMORY")
        .defaultValue(defaultMemoryLimit)
        .inRange(std::numeric_limits<unsigned long>().min(), std::numeric_limits<unsigned long>().max());

    program->add("player1-limits-time")
        .help("Time limit for player1 in milliseconds")
        .valueFromConfig("player1", "limits", "time")
        .valueFromArgument("--player1-limits-time")
        .valueFromEnvironmentVariable("LV_PLAYER1_LIMITS_TIME")
        .defaultValue(defaultTimeLimit)
        .inRange(std::numeric_limits<size_t>().min(), std::numeric_limits<size_t>().max());

    program->add("player2-exe")
        .help("Path to the executable for player2")
        .valueFromConfig("player2", "exe")
        .valueFromArgument("--player2-exe")
        .valueFromEnvironmentVariable("LV_PLAYER2_EXE")
        .defaultValue("player2");

    program->add("player2-limits-memory")
        .help("Memory limit for player2 in bytes")
        .valueFromConfig("player2", "limits", "memory")
        .valueFromArgument("--player2-limits-memory")
        .valueFromEnvironmentVariable("LV_PLAYER2_LIMITS_MEMORY")
        .defaultValue(defaultMemoryLimit)
        .inRange(std::numeric_limits<unsigned long>().min(), std::numeric_limits<unsigned long>().max());

    program->add("player2-limits-time")
        .help("Time limit for player2 in milliseconds")
        .valueFromConfig("player2", "limits", "time")
        .valueFromArgument("--player2-limits-time")
        .valueFromEnvironmentVariable("LV_PLAYER2_LIMITS_TIME")
        .defaultValue(defaultTimeLimit)
        .inRange(std::numeric_limits<size_t>().min(), std::numeric_limits<size_t>().max());

    program->add("debug-enable")
        .help("Enables debug messages")
        .valueFromConfig("debug", "enable")
        .valueFromArgument("--debug-enable")
        .valueFromEnvironmentVariable("LV_DEBUG_ENABLE")
        .possibleValues(true, false)
        .defaultValue(false)
        .implicit();

    program->add("debug-board")
        .help("Enables board display")
        .valueFromConfig("debug", "board")
        .valueFromArgument("--debug-board")
        .valueFromEnvironmentVariable("LV_DEBUG_BOARD")
        .possibleValues(true, false)
        .defaultValue(false)
        .implicit();
    // clang-format on

    try {
        program->load("./config.yml");
    } catch (const configuration::BadFile &) {
        if (std::filesystem::exists("./config.yml")) {
            LERROR("Failed to open config file, check permissions");
            return std::nullopt;
        }
        LWARN("No config file found, creating one");
        program->save("./config.yml");
    }

    try {
        program->parse(argc, argv);
    } catch (const std::exception &err) {
        std::cerr << err.what() << std::endl;
        std::cerr << program.value();
        return std::nullopt;
    }

    return program;
}

}

int MAIN(int argc, const char **argv)
{
    auto program_opt = initArgs(argc, argv);
    if (!program_opt.has_value()) {
        return 3;
    }
    try {
        auto &program = program_opt.value();

        if (!program["headless"].as<bool>()) {
            LFATAL("Not running in headless mode is currently not possible! Please use --headless");
            return 3;
        }

        LINFO("Starting {}{}", PROGRAM_NAME, PROGRAM_VERSION);

        if (program["debug-enable"].as<bool>()) {
            logging::setLevel(logging::Registry::LogLevel::debug);
        }

        // Register sigchld handler to check for player dying
        struct sigaction sa;

        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = sigchld_handler;

        sigaction(SIGCHLD, &sa, NULL);

        // Player load
        LDEBUG("Loading player 1 {}", program["player1-exe"].as<std::string>());
        lv::Player player1(
            program["player1-exe"].as<std::string>(), program["player1-limits-memory"].as<unsigned long>(),
            program["player1-limits-time"].as<size_t>(), 1
        );
        LDEBUG("Loading player 2 {}", program["player2-exe"].as<std::string>());
        lv::Player player2(
            program["player2-exe"].as<std::string>(), program["player2-limits-memory"].as<unsigned long>(),
            program["player2-limits-time"].as<size_t>(), 2
        );
        return liskvork(program, player1, player2);
    } catch (const std::exception &e) {
        LFATAL("Error at root!");
        LFATAL(e.what());
        return 3;
    }
    return 0;
}
