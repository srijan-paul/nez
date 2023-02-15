#pragma once

#include <cstdint>
#include <cstddef>

namespace emu {

struct CPU final {
  using Register = std::uint8_t;
  static constexpr size_t NumRegs = 6;

  Register PC;
  Register X;
  Register Y;
  Register Status;
};

}; // namespace emu

