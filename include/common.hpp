#pragma once

#include <cstdint>
#include <cstddef>

#define NEZ_DEBUG

namespace nez {

#ifdef NEZ_DEBUG
#define NEZ_ERROR(message) { fprintf(stderr, "[%s, line %d]: %s\n", __FILE__, __LINE__, message); abort(); }
#else
#define NEZ_ERROR(message) void(0)
#endif


using byte = std::uint8_t;

}

