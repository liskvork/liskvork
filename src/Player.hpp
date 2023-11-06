#ifndef D6FFAF17_E755_47B1_BCC1_772F8C11FADE
#define D6FFAF17_E755_47B1_BCC1_772F8C11FADE

#include <ext/stdio_filebuf.h> // NB: Specific to libstdc++
#include <filesystem>
#include <optional>

#include "CPipe.hpp"
#include "GameState.hpp"
#include "logging/logging.hpp"

namespace lv {

class Player {
public:
    Player(const std::filesystem::path &path, unsigned long memoryLimit, size_t timeLimit, uint8_t number);
    ~Player();

    NODISCARD const std::string &getName() const noexcept { return _name; }
    NODISCARD const std::string &getDescription() const noexcept { return _description; }
    NODISCARD const std::string &getVersion() const noexcept { return _version; }
    NODISCARD const std::string &getAuthor() const noexcept { return _author; }
    NODISCARD const std::string &getCountry() const noexcept { return _country; }
    NODISCARD const std::string &getWWW() const noexcept { return _www; }
    NODISCARD const std::string &getEmail() const noexcept { return _email; }

    NODISCARD int getPID() const noexcept { return _playerPID; }

    void printUnknown(const std::string &msg) const { LWARN("({}) {}> [UNKNOWN] {}", _name, _playerNumber, msg); }
    void printError(const std::string &msg) const { LERROR("({}) {}> [ERROR] {}", _name, _playerNumber, msg); }
    void printMessage(const std::string &msg) const { LINFO("({}) {}> [MESSAGE] {}", _name, _playerNumber, msg); }
    void printDebug(const std::string &msg) const { LDEBUG("({}) {}> [DEBUG] {}", _name, _playerNumber, msg); }

    /**
     * @brief Will call the correct print if needed
     *
     * @param line The line that the player sent
     * @return true The line had a print
     * @return false The line didn't have a print
     */
    bool handlePotentialPrint(const std::string &line) const;

    /**
     * @brief Initializes the state of the player
     *
     * @return true Initialization succeeded
     * @return false INitialization failed
     */
    bool initialize();

    /**
     * @brief Lets the player take a turn
     *
     * @param gameState The global game state
     * @return PlayerTurnResult The result of this turn
     */
    PlayerTurnResult takeTurn(GameState &gameState);

    void stop() noexcept { _stopped = true; }

private:
    std::string _name;
    std::string _description;
    std::string _version;
    std::string _author;
    std::string _country;
    std::string _www;
    std::string _email;
    const uint8_t _playerNumber;
    int _playerPID;
    const unsigned long _memoryLimit;
    const size_t _timeLimit;

    CPipe _write_pipe;
    CPipe _read_pipe;
    std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> _write_buf = nullptr;
    std::unique_ptr<__gnu_cxx::stdio_filebuf<char>> _read_buf = nullptr;
    std::ostream _stdin;
    std::istream _stdout;
    bool _stopped = false;
};

}

#endif /* D6FFAF17_E755_47B1_BCC1_772F8C11FADE */
