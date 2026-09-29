import unittest
from check_xctest_log import succeeded


class XCTestLogTests(unittest.TestCase):
    def test_success(self):
        self.assertTrue(succeeded("Executed 12 tests, with 0 failures\n** TEST EXECUTE SUCCEEDED **", 0))

    def test_failures_hidden_by_execute_failed_footer(self):
        self.assertFalse(succeeded("Test Suite 'WebPreviewWebKitTests' failed\nExecuted 3 tests, with 5 failures\n** TEST EXECUTE FAILED **", 65))

    def test_crash_followed_by_passing_tests(self):
        self.assertFalse(succeeded("Restarting after unexpected exit, crash, or test timeout\nExecuted 7 tests, with 0 failures\n** TEST EXECUTE SUCCEEDED **", 0))

    def test_empty_or_incomplete_run(self):
        for log in ["", "Executed 0 tests, with 0 failures\n** TEST EXECUTE SUCCEEDED **", "Executed 7 tests, with 0 failures"]:
            self.assertFalse(succeeded(log, 0))

    def test_nonzero_exit_is_not_suppressed(self):
        self.assertFalse(succeeded("Executed 12 tests, with 0 failures\n** TEST EXECUTE SUCCEEDED **", 65))


if __name__ == '__main__':
    unittest.main()
