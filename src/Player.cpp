#include <filesystem>
#include <optional>

#include "Player.hpp"
#include "logging/logging.hpp"

namespace lv {

std::optional<Player> Player::loadFromBinary(const std::filesystem::path &path)
{
    std::optional<Player> player = std::nullopt;

    if (!std::filesystem::exists(path) || !std::filesystem::is_regular_file(path)) {
        LFATAL("Cannot open player executable with path: {}", path.string());
        return std::nullopt;
    }

    // TODO(huntears): https://stackoverflow.com/a/5784634 -> Launch program with mem limit

    return player;
}

Player::Player(
    std::string &&name, std::optional<std::string> &&version, std::optional<std::string> &&author,
    std::optional<std::string> &&country, std::optional<std::string> &&www, std::optional<std::string> &&email
):
    _name(std::move(name)),
    _version(std::move(version)),
    _author(std::move(author)),
    _country(std::move(country)),
    _www(std::move(www)),
    _email(std::move(email))
{
    LDEBUG("Loaded player with name: {}", _name);
}

}
