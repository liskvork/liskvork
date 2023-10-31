#ifndef D6FFAF17_E755_47B1_BCC1_772F8C11FADE
#define D6FFAF17_E755_47B1_BCC1_772F8C11FADE

#include <filesystem>
#include <optional>

namespace lv {

class Player {
public:
    static std::optional<Player> loadFromBinary(const std::filesystem::path &path);

private:
    Player(
        std::string &&name, std::optional<std::string> &&version, std::optional<std::string> &&author,
        std::optional<std::string> &&country, std::optional<std::string> &&www, std::optional<std::string> &&email
    );

    std::string _name;
    std::optional<std::string> _version;
    std::optional<std::string> _author;
    std::optional<std::string> _country;
    std::optional<std::string> _www;
    std::optional<std::string> _email;
};

}

#endif /* D6FFAF17_E755_47B1_BCC1_772F8C11FADE */
