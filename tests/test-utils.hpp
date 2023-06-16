#include <cstddef>
#include <cstdio>
#include <cstdlib>

enum class TestResult : int { Pass = 0, Fail = 1 };

struct TestContext final {
  std::size_t failed = 0;
  std::size_t passed = 0;

  TestContext() = default;
  TestContext(TestContext const &) = delete;
  TestContext operator=(TestContext const &) = delete;
  TestContext operator=(TestContext &) = delete;

  ~TestContext() {
    if (failed > 0) {
      fprintf(stderr, "%zu failed, %zu passed.\n", failed, passed);
      std::exit(1);
    }
    exit(0);
  }
};

#define TEST(CTX, NAME)                                                        \
  {                                                                            \
    printf("%10s : ", #NAME);                                                  \
    fflush(stdout);                                                            \
    const TestResult result = NAME();                                          \
    if (result == TestResult::Fail) {                                          \
      puts(": FAIL");                                                          \
      ++CTX.failed;                                                            \
    } else {                                                                   \
      puts("PASS");                                                            \
      ++CTX.passed;                                                            \
    }                                                                          \
  }

#define ASSERT(expr)                                                           \
  if (!(expr)) {                                                               \
    fprintf(stderr, "%s (%s:%d) ", #expr, __func__, __LINE__);                 \
    return TestResult::Fail;                                                   \
  }
#define ASSERT_EQ(a, b) ASSERT((a) == (b))
#define ASSERT_NOT_EQ(a, b) ASSERT((a) != (b))
#define ASSERT_TRUE(a) ASSERT((a) == true)
#define ASSERT_FALSE(a) ASSERT((a) == false)
#define FATAL()                                                                \
  {                                                                            \
    fprintf(stderr, "FATAL ERROR! %s:%d\n", __func__, __LINE__);               \
    std::exit(-1);                                                             \
  }
