#include <common.hpp>
#include <cpu.hpp>

namespace nez {

void CPU::step() {
  const auto instr = next_instr();
  switch (instr) {
  case Op::LDAimm: {
    this->rA = this->next_byte();
    break;
  }

  default: {
    NEZ_ERROR("Not implemented");
    break;
  }
  }
}

} // namespace nez
