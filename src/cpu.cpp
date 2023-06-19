#include <common.hpp>
#include <cpu.hpp>

namespace nez {

// Instruction set reference:
// https://www.masswerk.at/6502/6502_instruction_set.html
void CPU::step() {
  const auto instr = next_instr();
  switch (instr) {
  case Op::LDAimm: {
    this->rA = this->next_byte();
    break;
  }

  case Op::LDAzrpg: {
    const nez::Byte addr = this->next_byte();
    this->rA = this->read_memory(addr);
    break;
  }

  default: {
    NEZ_ERROR("Not implemented");
  }
  }
}

} // namespace nez
