#include "test-utils.hpp"
#include <cpu.hpp>

using namespace nez;

TestResult instr_test() {
  CPU cpu;
  cpu.write_memory_direct(0, Op::LDAimm);
  cpu.write_memory_direct(1, 25);
  cpu.step();
  ASSERT_EQ(cpu.reg_val(CPU::RegisterName::a), 25);

  return TestResult::Pass;
}

int main() {
  TestContext ctx;
  TEST(ctx, instr_test);
}
