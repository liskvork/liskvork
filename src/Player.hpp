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

private:
    std::string _name;
    std::optional<std::string> _version;
    std::optional<std::string> _author;
    std::optional<std::string> _country;
    std::optional<std::string> _www;
    std::optional<std::string> _email;
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
