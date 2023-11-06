#include <chrono>
#include <csignal>
#include <cstdio>
#include <filesystem>
#include <iostream>
#include <optional>
#include <regex>
#include <stdexcept>
#include <string>
#include <sys/resource.h>
#include <unistd.h>

#include "GameState.hpp"
#include "Player.hpp"
#include "logging/logging.hpp"

namespace lv {

Player::Player(const std::filesystem::path &path, unsigned long memoryLimit, size_t timeLimit, uint8_t playerNumber):
    _playerNumber(playerNumber),
    _playerPID(-1),
    _memoryLimit(memoryLimit),
    _timeLimit(timeLimit),
    _stdin(nullptr),
    _stdout(nullptr)
{
    if (!std::filesystem::exists(path) || !std::filesystem::is_regular_file(path)) {
        LFATAL("Cannot open player executable with path: {}", path.string());
        throw std::runtime_error("Could not create new player");
    }
    _playerPID = fork();
    if (_playerPID == -1) {
        throw std::runtime_error("Failed to start child process");
    }
    if (_playerPID == 0) { // In child process
        // Set the memory limit for the new player
        if (memoryLimit) {
            const struct rlimit limits = {memoryLimit, memoryLimit};
            setrlimit(RLIMIT_DATA, &limits);
        }

        ::dup2(_write_pipe.read_fd(), STDIN_FILENO);
        ::dup2(_read_pipe.write_fd(), STDOUT_FILENO);
        _write_pipe.close();
        _read_pipe.close();
        const char *playerArgv[2] = {path.c_str(), nullptr};
        if (execv(path.c_str(), (char *const *) playerArgv) == -1) {
            // Note: no point writing to stdout here, it has been redirected
            std::cerr << "Error: Failed to launch program" << std::endl;
            ::exit(1);
        }
    }
    ::close(_write_pipe.read_fd());
    ::close(_read_pipe.write_fd());
    _write_buf = std::make_unique<__gnu_cxx::stdio_filebuf<char>>(_write_pipe.write_fd(), std::ios::out);
    _read_buf = std::make_unique<__gnu_cxx::stdio_filebuf<char>>(_read_pipe.read_fd(), std::ios::in);
    _stdin.rdbuf(_write_buf.get());
    _stdout.rdbuf(_read_buf.get());
    LDEBUG("Getting about data about {}", path.string());
    _stdin << "ABOUT" << std::endl;
    const std::regex word_regex("(\\w+)=\"([^\"]*)\"");
    bool gotName = false;
    while (!gotName) {
        std::string line;
        std::getline(_stdout, line);
        if (handlePotentialPrint(line))
            continue;
        const auto words_begin = std::sregex_iterator(line.begin(), line.end(), word_regex);
        const auto words_end = std::sregex_iterator();
        for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
            const std::smatch match = *i;
            const auto key = match[1].str();
            const auto value = match[2].str();
            if (key == "name") {
                _name = value;
                gotName = true;
            } else if (key == "version")
                _version = value;
            else if (key == "author")
                _author = value;
            else if (key == "country")
                _author = value;
            else if (key == "www")
                _www = value;
            else if (key == "description")
                _description = value;
            else
                LWARN("Unknown key {} with value {} from {}", key, value, path.string());
        }
    }
    LDEBUG("Loaded player with name: {}", _name);
}

bool Player::handlePotentialPrint(const std::string &line) const
{
    if (line.starts_with("UNKNOWN "))
        printUnknown(line.substr(8));
    else if (line.starts_with("ERROR "))
        printError(line.substr(6));
    else if (line.starts_with("MESSAGE "))
        printMessage(line.substr(8));
    else if (line.starts_with("DEBUG "))
        printDebug(line.substr(6));
    else
        return false;
    return true;
}

bool Player::initialize()
{
    LDEBUG("Initializing player({})", _name);
    _stdin << "START 20" << std::endl;
    while (1) {
        std::string line;
        std::getline(_stdout, line);
        if (handlePotentialPrint(line))
            continue;
        if (line != "OK") {
            LFATAL("Could not initialize player({}) -> {}", _name, line);
            return false;
        }
        break;
    };
    _stdin << "INFO timeout_match " << 0 << std::endl;
    _stdin << "INFO timeout_turn " << _timeLimit << std::endl;
    _stdin << "INFO max_memory " << _memoryLimit << std::endl;
    LDEBUG("Initialized player({})", _name);
    return true;
}

namespace {

bool isWin(const GameState &gameState)
{
    // Absolutely horrendous function, but it's fast enough so idrc
    // Taken from https://stackoverflow.com/a/38211417 cause I couldn't be bothered :)
    const auto lastMove = gameState.lastTurn.value();
    const auto player = gameState.playArea.at(lastMove.x).at(lastMove.y);
    const auto &board = gameState.playArea;

    // horizontalCheck
    for (uint8_t j = 0; j < 20 - 4; j++) {
        for (uint8_t i = 0; i < 20; i++) {
            if (board[i][j] == player && board[i][j + 1] == player && board[i][j + 2] == player &&
                board[i][j + 3] == player && board[i][j + 4] == player) {
                return true;
            }
        }
    }
    // verticalCheck
    for (uint8_t i = 0; i < 20 - 4; i++) {
        for (uint8_t j = 0; j < 20; j++) {
            if (board[i][j] == player && board[i + 1][j] == player && board[i + 2][j] == player &&
                board[i + 3][j] == player && board[i + 4][j] == player) {
                return true;
            }
        }
    }
    // ascendingDiagonalCheck
    for (uint8_t i = 4; i < 20; i++) {
        for (uint8_t j = 0; j < 20 - 4; j++) {
            if (board[i][j] == player && board[i - 1][j + 1] == player && board[i - 2][j + 2] == player &&
                board[i - 3][j + 3] == player && board[i - 4][j + 4] == player)
                return true;
        }
    }
    // descendingDiagonalCheck
    for (uint8_t i = 4; i < 20; i++) {
        for (uint8_t j = 4; j < 20; j++) {
            if (board[i][j] == player && board[i - 1][j - 1] == player && board[i - 2][j - 2] == player &&
                board[i - 3][j - 3] == player && board[i - 4][j - 4] == player)
                return true;
        }
    }
    return false;
}

}

PlayerTurnResult Player::takeTurn(GameState &gameState)
{
    const bool isFirstTurn = !gameState.lastTurn.has_value();

    if (_stopped)
        return PlayerTurnResult::LOSE;
    if (isFirstTurn) {
        LDEBUG("Sending \"BEGIN\" to player{}({})", _playerNumber, _name);
        _stdin << "BEGIN" << std::endl;
    } else {
        LDEBUG(
            "Sending \"TURN {},{}\" to player{}({})", (int) gameState.lastTurn->x, (int) gameState.lastTurn->y,
            _playerNumber, _name
        );
        _stdin << "TURN " << (int) gameState.lastTurn->x << "," << (int) gameState.lastTurn->y << std::endl;
    }
    const auto startTurn = std::chrono::high_resolution_clock::now();
    while (1) {
        std::string line;
        std::getline(_stdout, line);
        if (handlePotentialPrint(line))
            continue;
        LDEBUG("Move from player{}({}): {}", _playerNumber, _name, line);
        int x;
        int y;
        int n = sscanf(line.c_str(), "%d,%d", &x, &y);
        if (n != 2) {
            LERROR("Impossible to parse move \"{}\", player{}({}) loses!", line, _playerNumber, _name);
            return PlayerTurnResult::LOSE;
        }
        if (!(x >= 0 && x < 20) || !(y >= 0 && y < 20)) {
            LERROR("Illegal move \"{}\" (OutOfBounds) from player{}({})!", line, _playerNumber, _name);
            return PlayerTurnResult::LOSE;
        }
        if (gameState.playArea.at((uint8_t) x).at((uint8_t) y) != SquareState::EMPTY) {
            LERROR("Illegal move \"{}\" (SpaceAlreadyOccupied) from player{}({})!", line, _playerNumber, _name);
            return PlayerTurnResult::LOSE;
        }
        const auto endTurn = std::chrono::high_resolution_clock::now();
        const auto turnDuration = endTurn - startTurn;
        const auto turnDurationMilliseconds =
            std::chrono::duration_cast<std::chrono::milliseconds>(turnDuration).count();
        LDEBUG("Player{}({})'s turn took {}ms/{}ms", _playerNumber, _name, turnDurationMilliseconds, _timeLimit);
        if (_timeLimit && (size_t) turnDurationMilliseconds > _timeLimit) {
            LERROR("Player{}({}) took too long to take its turn!", _playerNumber, _name);
            return PlayerTurnResult::LOSE;
        }
        gameState.playArea.at((uint8_t) x).at((uint8_t) y) =
            _playerNumber == 1 ? SquareState::PLAYER1 : SquareState::PLAYER2;
        gameState.lastTurn = Turn((uint8_t) x, (uint8_t) y);
        // TODO(huntears): Check remaining time
        return isWin(gameState) ? PlayerTurnResult::WIN : PlayerTurnResult::NOTHING;
    };
    // Literally impossible to reach
    __builtin_unreachable();
}

Player::~Player()
{
    // Yes I am stopping the player with a sigkill, what about it?
    LDEBUG("Killing player {}", _name);
    kill(_playerPID, 9);
}

}
