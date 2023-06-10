#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace emu {

enum class Op {
  // Load operand into accumulator.
  LDAimm = 0x0A9,

  // JAMx instructions freeze the CPU. 
  JAM0 = 0x02,
  JAM1 = 0x12,
  JAM2 = 0x22,
  JAM3 = 0x32,
  JAM4 = 0x42,
  JAM5 = 0x52,
  JAM6 = 0x62,
  JAM7 = 0x72,
  JAM9 = 0x92,
  JAMB = 0xB2,
  JAMD = 0xB2,
  JAMF = 0xF2,
};

/// \brief Emulator for a MOS 6502 CPU.
/// Instruction set reference:
/// https://www.masswerk.at/6502/6502_instruction_set.html
struct CPU final {
  using Register = std::uint8_t;

  [[nodiscard]] std::byte read_memory(const std::uint16_t address) const;
  void write_memory(const std::uint16_t address, std::byte value) const;
  void run();
  void step();

private:
  // Memory map reference: https://www.nesdev.org/wiki/CPU_memory_map
  Register rPC;
  Register rX;
  Register rY;
  // Accumulator.
  Register rA;
  // NV-BDIZC
  // N - Negative
  // V - Overflow
  // _
  // B - Break
  // D - Decimal
  // I - Interrupt
  // Z - zero
  // C - carry
  Register rStatus;
  // Stack Pointer, also called the "P" register sometimes.
  Register rSP;
  std::array<std::byte, 0xFFFF> memory;
};

}; // namespace emu
