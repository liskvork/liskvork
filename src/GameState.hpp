#ifndef A7D77E16_1E0B_4A0A_AB5A_189D36542A21
#define A7D77E16_1E0B_4A0A_AB5A_189D36542A21

#include <array>
#include <cstdint>
#include <optional>

namespace lv {

enum class SquareState {
    EMPTY,
    PLAYER1,
    PLAYER2
};

struct Turn {
    uint8_t x;
    uint8_t y;

public:
    Turn(uint8_t x, uint8_t y):
        x(x),
        y(y)
    {
    }
};

struct GameState {
    std::array<std::array<SquareState, 20>, 20> playArea;
    std::optional<Turn> lastTurn = std::nullopt;
};

enum class PlayerTurnResult {
    NOTHING,
    WIN,
    LOSE, // Can only happen upon an illegal move
};

}

#endif /* A7D77E16_1E0B_4A0A_AB5A_189D36542A21 */
