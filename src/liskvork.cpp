#include <array>
#include <bits/iterator_concepts.h>
#include <chrono>
#include <optional>
#include <sys/wait.h>
#include <thread>

#include "GameState.hpp"
#include "Player.hpp"
#include "configuration/ConfigHandler.hpp"
#include "liskvork.hpp"
#include "logging/logging.hpp"

namespace {

std::thread gameLoopThread;
bool gameLoopRunning = true;

std::string stateStr(lv::SquareState state)
{
    if (state == lv::SquareState::EMPTY)
        return " ";
    if (state == lv::SquareState::PLAYER1)
        return "O";
    if (state == lv::SquareState::PLAYER2)
        return "X";
    // If you get here you have some memory corruption, ain't good ;w;
    return "?";
}

void printGameBoard(lv::GameState &gameState)
{
    // This is one hell of an ugly function damn
    auto &board = gameState.playArea;
    LDEBUG("Current board:");
    for (size_t y = 0; y < 20; y++) {
        LDEBUG(
            "|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|", stateStr(board.at(0).at(y)),
            stateStr(board.at(0).at(y)), stateStr(board.at(1).at(y)), stateStr(board.at(2).at(y)),
            stateStr(board.at(3).at(y)), stateStr(board.at(4).at(y)), stateStr(board.at(5).at(y)),
            stateStr(board.at(6).at(y)), stateStr(board.at(7).at(y)), stateStr(board.at(8).at(y)),
            stateStr(board.at(9).at(y)), stateStr(board.at(10).at(y)), stateStr(board.at(11).at(y)),
            stateStr(board.at(12).at(y)), stateStr(board.at(13).at(y)), stateStr(board.at(14).at(y)),
            stateStr(board.at(15).at(y)), stateStr(board.at(16).at(y)), stateStr(board.at(17).at(y)),
            stateStr(board.at(18).at(y)), stateStr(board.at(19).at(y))
        );
    }
    LDEBUG("End current board");
}

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

int gameLoop(lv::Player &player1, lv::Player &player2, const configuration::ConfigHandler &config)
{
    const auto printBoard = config["debug-board"].as<bool>();

    lv::GameState gameState;
    for (auto &i : gameState.playArea)
        for (auto &y : i)
            y = lv::SquareState::EMPTY;

    while (gameLoopRunning) {
        auto player1_res = player1.takeTurn(gameState);
        if (printBoard)
            printGameBoard(gameState);
        if (player1_res != lv::PlayerTurnResult::NOTHING)
            return handleEndGame(1, player1_res);
        auto player2_res = player2.takeTurn(gameState);
        if (printBoard)
            printGameBoard(gameState);
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
        // Currently commented because it causes a crash at the end of the program
        // LFATAL("Player with PID {} died! (Is that a crash?)", p);
    }
}

int liskvork(const configuration::ConfigHandler &config, lv::Player &player1, lv::Player &player2)
{
    LINFO("Starting game with player1({}) and player2({}).", player1.getName(), player2.getName());
    if (config["headless"].as<bool>()) {
        LINFO("Currently running in headless mode.");
    }
    if (!player1.initialize() || !player2.initialize())
        return 3;
    int match_res = 0;
    bool match_ended = false;
    gameLoopThread = std::thread([&player1, &player2, &match_res, &match_ended, &config]() {
        match_res = gameLoop(player1, player2, config);
        match_ended = true;
    });
    while (!match_ended) {
        // Commands commented as I don't want to handle getline timeouts quite yet
        // That's a problem for future me

        // std::string line;
        // if (!std::getline(std::cin, line))
        //     break;
        // if (line.starts_with("STOP"))
        //     break;
        // TODO(huntears): Maybe implement some more commands :/
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    gameLoopRunning = false;
    gameLoopThread.join();
    if (match_res == 0)
        LINFO("Match stopped");
    else if (match_res == 1)
        LINFO("Player1({}) won!", player1.getName());
    else if (match_res == 2)
        LINFO("Player2({}) won!", player2.getName());
    return match_res;
}
