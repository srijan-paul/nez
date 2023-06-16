#pragma once

#include <array>
#include <common.hpp>
#include <cstddef>
#include <cstdint>

namespace nez {

enum class Op : nez::byte {
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
  using Register = byte;

  /// Named values used to refer to registers.
  enum class RegisterName : std::size_t { a = 0, x, y, pc, status, sp };

  [[nodiscard]] inline nez::byte
  read_memory(const std::uint16_t address) const {
    return this->memory[address];
  }

  void write_memory(const std::uint16_t address, nez::byte value);
  void write_memory_direct(const std::size_t index, nez::byte value) {
    this->memory[index] = value;
  }

  void write_memory_direct(const std::size_t index, nez::Op value) {
    this->memory[index] = static_cast<nez::byte>(value);
  }
  void run();
  void step();

  [[nodiscard]] Register reg_val(RegisterName const reg) const noexcept {
    switch (reg) {
    case RegisterName::pc:
      return rPC;
    case RegisterName::x:
      return rX;
    case RegisterName::y:
      return rY;
    case RegisterName::a:
      return rA;
    case RegisterName::status:
      return rStatus;
    case RegisterName::sp:
      return rSP;
    }
  }

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
  std::array<nez::byte, 0xFFFF> memory;

  /// \brief fetch the next instruction to execute.
  [[nodiscard]] inline Op next_instr() {
    const auto instr = static_cast<Op>(this->memory[this->rPC]);
    ++this->rPC;
    return instr;
  }

  [[nodiscard]] inline nez::byte next_byte() {
    const nez::byte operand = this->memory[this->rPC];
    ++this->rPC;
    return operand;
  }
};
}; // namespace nez
