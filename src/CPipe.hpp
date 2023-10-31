#ifndef BDE90F25_0E94_4735_B52E_4B7950051422
#define BDE90F25_0E94_4735_B52E_4B7950051422

#include <array>
#include <stdexcept>
#include <unistd.h>

#include "options.hpp"

class CPipe {
private:
    std::array<int, 2> fd {};

public:
    NODISCARD inline int read_fd() const noexcept { return fd[0]; }
    NODISCARD inline int write_fd() const noexcept { return fd[1]; }
    CPipe()
    {
        if (pipe(fd.data()) != 0) {
            throw std::runtime_error("Failed to create pipe");
        }
    }
    CPipe(CPipe &&other) noexcept
    {
        fd[0] = other.read_fd();
        fd[1] = other.write_fd();
        other.fd[0] = -1;
        other.fd[1] = -1;
    }
    CPipe(CPipe &other) = delete;
    CPipe &operator=(CPipe &other) = delete;
    CPipe &operator=(CPipe &&other) = delete;

    void close() noexcept { ::close(fd[1]); }

    ~CPipe() { close(); }
};

#endif /* BDE90F25_0E94_4735_B52E_4B7950051422 */
