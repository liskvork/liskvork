#include <array>
#include <bits/iterator_concepts.h>
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

int handleEndGame(uint8_t playerNumber, lv::PlayerTurnResult res)
{
    // Yes that is disgusting but it will literally be called once, so who cares
    if (playerNumber == 1 && res == lv::PlayerTurnResult::LOSE)
        return 2;
    if (playerNumber == 1 && res == lv::PlayerTurnResult::WIN)
        return 1;
    if (playerNumber == 2 && res == lv::PlayerTurnResult::LOSE)
        return 1;
    if (playerNumber == 2 && res == lv::PlayerTurnResult::WIN)
        return 2;
    // I could use std::unreachable but I don't want a dep on C++23
    __builtin_unreachable();
}

int gameLoop(lv::Player &player1, lv::Player &player2)
{
    lv::GameState gameState;
    for (auto &i : gameState.playArea)
        for (auto &y : i)
            y = lv::SquareState::EMPTY;

    while (gameLoopRunning) {
        auto player1_res = player1.takeTurn(gameState);
        if (player1_res != lv::PlayerTurnResult::NOTHING)
            return handleEndGame(1, player1_res);
        auto player2_res = player2.takeTurn(gameState);
        if (player2_res != lv::PlayerTurnResult::NOTHING)
            return handleEndGame(2, player2_res);
    }
    return 0;
}

}

void sigchld_handler(UNUSED int sig)
{
    pid_t p;
    int status;

    while ((p = waitpid(-1, &status, WNOHANG)) != -1) {
        if (p == 0)
            break;
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
