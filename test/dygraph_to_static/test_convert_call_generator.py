#   Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import unittest

from dygraph_to_static_util import (
    ast_only_test,
    dy2static_unittest,
    test_and_compare_with_new_ir,
)

import paddle
from paddle.jit import to_static
from paddle.jit.dy2static.convert_call_func import translator_logger


def dyfunc_generator():
    for i in range(100):
        yield paddle.to_tensor([i] * 10)


def main_func():
    """Error will raise, but we only report a warning not intercept"""
    for i in dyfunc_generator():
        print(i)


@dy2static_unittest
class TestConvertGenerator(unittest.TestCase):
    # fallback will ok.
    @ast_only_test
    @test_and_compare_with_new_ir(False)
    def test_raise_error(self):
        translator_logger.verbosity_level = 1
        with self.assertLogs(
            translator_logger.logger_name, level='WARNING'
        ) as cm:
            to_static(main_func)()
            self.assertRegex(
                cm.output[0],
                "Your function:`dyfunc_generator` doesn't support "
                "to transform to static function because it is a "
                "generator function",
            )


if __name__ == '__main__':
    unittest.main()
