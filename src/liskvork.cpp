#include <array>
#include <optional>
#include <sys/wait.h>
#include <thread>

#include "GameState.hpp"
#include "Player.hpp"
#include "liskvork.hpp"
#include "logging/logging.hpp"

namespace {

std::thread gameLoopThread;
bool gameLoopRunning = true;

int gameLoop(lv::Player &player1, lv::Player &player2)
{
    lv::GameState gameState;
    for (auto &i : gameState.playArea)
        for (auto &y : i)
            y = lv::SquareState::EMPTY;

    while (gameLoopRunning) {
        if (player1.takeTurn(gameState)) {
            LINFO("Player1({}) won!");
            return 1;
        }
        if (player2.takeTurn(gameState)) {
            LINFO("Player2({}) won!");
            return 2;
        }
    }
    return 0;
}

}

void sigchld_handler(UNUSED int sig)
{
    pid_t p;
    int status;

    while ((p = waitpid(-1, &status, WNOHANG)) != -1) {
        // TODO(huntears): Properly handle the death of a player
        LFATAL("Player with PID {} died! (Is that a crash?)", p);
    }
}

int liskvork(const configuration::ConfigHandler &config, lv::Player &player1, lv::Player &player2)
{
    LINFO("Starting game with player1({}) and player2({}).", player1.getName(), player2.getName());
    if (config["headless"].as<bool>()) {
        LINFO("Currently running in headless mode.");
    }
    if (!player1.initialize() || !player2.initialize())
        return 1;
    gameLoopThread = std::thread([&player1, &player2]() {
        gameLoop(player1, player2);
    });
    while (1) {
        std::string line;
        if (!std::getline(std::cin, line))
            break;
        if (line.starts_with("STOP"))
            break;
        // TODO(huntears): Maybe implement some more commands :/
    }
    gameLoopRunning = false;
    gameLoopThread.join();
    return 0;
}
