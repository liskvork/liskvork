#include <filesystem>
#include <optional>
#include <sys/resource.h>
#include <unistd.h>

#include "Player.hpp"
#include "logging/logging.hpp"

namespace lv {

std::optional<Player>
Player::loadFromBinary(const std::filesystem::path &path, unsigned long memoryLimit, size_t timeLimit)
{
    std::optional<Player> player = std::nullopt;

    if (!std::filesystem::exists(path) || !std::filesystem::is_regular_file(path)) {
        LFATAL("Cannot open player executable with path: {}", path.string());
        return std::nullopt;
    }

    // TODO(huntears): https://stackoverflow.com/a/5784634 -> Launch program with mem limit
    const int mainProcessID = getpid();
    const int newPID = fork();
    if (newPID == 0) {
        // We are in the new process here

        // Set the memory limit for the new player
        const struct rlimit limits = {memoryLimit, memoryLimit};
        setrlimit(RLIMIT_DATA, &limits);

        const char *playerArgv[2] = {path.c_str(), nullptr};
        execv(path.c_str(), (char *const *) playerArgv);
    }

    return player;
}

Player::Player(
    std::string &&name, std::optional<std::string> &&version, std::optional<std::string> &&author,
    std::optional<std::string> &&country, std::optional<std::string> &&www, std::optional<std::string> &&email, int PID,
    unsigned long memoryLimit, size_t timeLimit
):
    _name(std::move(name)),
    _version(std::move(version)),
    _author(std::move(author)),
    _country(std::move(country)),
    _www(std::move(www)),
    _email(std::move(email)),
    _playerPID(PID),
    _memoryLimit(memoryLimit),
    _timeLimit(timeLimit)
{
    LDEBUG("Loaded player with name: {}", _name);
}

}
