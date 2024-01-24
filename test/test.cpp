#include <gtest/gtest.h>

namespace testing {
TEST(MyTestSuit, MyTestCase)
{
    ASSERT_EQ(84 / 2, 42);
    ASSERT_EQ(21 * 2, 42);
}
}
