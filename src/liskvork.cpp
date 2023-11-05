#include <sys/wait.h>

#include "liskvork.hpp"
#include "logging/logging.hpp"

void sigchld_handler(UNUSED int sig)
{
    pid_t p;
    int status;

    while ((p = waitpid(-1, &status, WNOHANG)) != -1) {
        // TODO(huntears): Handle the death of a player
    }
}

int liskvork(const configuration::ConfigHandler &config, lv::Player &player1, lv::Player &player2)
{
    LINFO("Starting game with player1({}) and player2({}).", player1.getName(), player2.getName());
    if (config["headless"].as<bool>()) {
        LINFO("Currently running in headless mode.");
    }
    while (1) {
        std::string line;
        if (!std::getline(std::cin, line))
            break;
        if (line.starts_with("STOP"))
            break;
        // TODO(huntears): Maybe implement some more commands :/
    }
    return 0;
}
