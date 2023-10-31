#ifndef OPTIONS_HPP
#define OPTIONS_HPP

#include <cstddef>

#ifndef PROGRAM_NAME
#define PROGRAM_NAME "liskvork"
#endif

#ifndef PROGRAM_VERSION
#define PROGRAM_VERSION "dev"
#endif

#ifndef NODISCARD
#define NODISCARD [[nodiscard]]
#endif

#ifndef UNUSED
#define UNUSED [[maybe_unused]]
#endif

// 70 MB
constexpr unsigned long defaultMemoryLimit = 70000000;

// 5 seconds
constexpr size_t defaultTimeLimit = 5000;

#endif // OPTIONS_HPP
