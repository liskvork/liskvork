#ifndef D6FFAF17_E755_47B1_BCC1_772F8C11FADE
#define D6FFAF17_E755_47B1_BCC1_772F8C11FADE

#include <ext/stdio_filebuf.h> // NB: Specific to libstdc++
#include <filesystem>
#include <optional>

#include "CPipe.hpp"

namespace lv {

class Player {
public:
    Player(const std::filesystem::path &path, unsigned long memoryLimit, size_t timeLimit);

    NODISCARD const std::string &getName() const noexcept { return _name; }
    NODISCARD const std::string &getVersion() const noexcept { return _version; }
    NODISCARD const std::string &getAuthor() const noexcept { return _author; }
    NODISCARD const std::string &getCountry() const noexcept { return _country; }
    NODISCARD const std::string &getWWW() const noexcept { return _www; }
    NODISCARD const std::string &getEmail() const noexcept { return _email; }

private:
    std::string _name;
    std::string _description;
    std::string _version;
    std::string _author;
    std::string _country;
    std::string _www;
    std::string _email;
    int _playerPID;
    unsigned long _memoryLimit;
    size_t _timeLimit;

    CPipe _write_pipe;
    CPipe _read_pipe;
    std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> _write_buf = nullptr;
    std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> _read_buf = nullptr;
    std::ostream _stdin;
    std::istream _stdout;
};

}

#endif /* D6FFAF17_E755_47B1_BCC1_772F8C11FADE */
