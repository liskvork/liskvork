#include <filesystem>
#include <iostream>
#include <optional>
#include <sys/resource.h>
#include <unistd.h>

#include "Player.hpp"
#include "logging/logging.hpp"

namespace lv {

Player::Player(const std::filesystem::path &path, unsigned long memoryLimit, size_t timeLimit):
    _playerPID(-1),
    _memoryLimit(memoryLimit),
    _timeLimit(timeLimit),
    _stdin(nullptr),
    _stdout(nullptr)
{
    if (!std::filesystem::exists(path) || !std::filesystem::is_regular_file(path)) {
        LFATAL("Cannot open player executable with path: {}", path.string());
    }
    _playerPID = fork();
    if (_playerPID == -1) {
        throw std::runtime_error("Failed to start child process");
    }
    if (_playerPID == 0) { // In child process
        // Set the memory limit for the new player
        const struct rlimit limits = {memoryLimit, memoryLimit};
        setrlimit(RLIMIT_DATA, &limits);

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
    LDEBUG("Loaded player with name: {}", _name);
}
}
