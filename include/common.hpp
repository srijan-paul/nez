#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>

#define NEZ_DEBUG

namespace nez {

#ifdef NEZ_DEBUG
#define NEZ_ERROR(message)                                                     \
  {                                                                            \
    fprintf(stderr, "[%s, line %d]: %s\n", __FILE__, __LINE__, message);       \
    abort();                                                                   \
  }
#else
#define NEZ_ERROR(message) void(0)
#endif

using Byte = std::uint8_t;

} // namespace nez
