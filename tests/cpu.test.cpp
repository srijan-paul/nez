#include <cpu.hpp>
#include <array>
#include "test-utils.hpp"

using namespace nez;

template <std::size_t const N>
std::unique_ptr<CPU> cpu_with_mem(std::array<nez::Byte, N> const& mem) {
  auto cpu = std::make_unique<CPU>();
  for (std::uint8_t i = 0; i < N; ++i) {
    cpu->write_memory_direct(i, mem[i]);
  }
  return cpu;
}

constexpr nez::Byte op(Op instr) noexcept {
  return static_cast<nez::Byte>(instr);
}

TestResult instr_test() {
  // LDA #0x12
  auto const cpu = cpu_with_mem<2>({{
    op(Op::LDAimm),
    0x12
  }});
  cpu->step();
  ASSERT_EQ(cpu->reg_val(CPU::RegisterName::a), 0x12);

  auto const cpu2 = cpu_with_mem<2>({{
    op(Op::LDAzrpg),
    0x01
  }}) ;


  return TestResult::Pass;
}

int main() {
  TestContext ctx;
  TEST(ctx, instr_test);
}

