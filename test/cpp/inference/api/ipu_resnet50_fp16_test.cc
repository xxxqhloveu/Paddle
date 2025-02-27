/* Copyright (c) 2022 PaddlePaddle Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. */

#include <glog/logging.h>
#include <gtest/gtest.h>

#include <cmath>

#include "paddle/utils/flags.h"
#include "test/cpp/inference/api/tester_helper.h"

namespace paddle {
namespace inference {

// Compare results with 1 batch
TEST(Analyzer_Resnet50_ipu, compare_results_1_batch) {
  std::string model_dir = FLAGS_infer_model + "/" + "model";
  AnalysisConfig config;
  // ipu_device_num, ipu_micro_batch_size, ipu_enable_pipelining
  config.EnableIpu(1, 1, false);
  // ipu_enable_fp16, ipu_replica_num, ipu_available_memory_proportion,
  // ipu_enable_half_partial
  config.SetIpuConfig(true, 1, 1.0, true);
  config.SetModel(model_dir + "/model", model_dir + "/params");

  std::vector<PaddleTensor> inputs;
  auto predictor = CreatePaddlePredictor(config);
  const int batch = 1;
  const int channel = 3;
  const int height = 318;
  const int width = 318;
  const int input_num = batch * channel * height * width;
  std::vector<float> input(input_num, 1);

  PaddleTensor in;
  in.shape = {batch, channel, height, width};
  in.data =
      PaddleBuf(static_cast<void*>(input.data()), input_num * sizeof(float));
  in.dtype = PaddleDType::FLOAT32;
  ConvertFP32toFP16(in);
  inputs.emplace_back(in);

  std::vector<PaddleTensor> outputs;

  ASSERT_TRUE(predictor->Run(inputs, &outputs));

  const std::vector<float> truth_values = {
      127.779f,  738.165f,  1013.22f,  -438.17f,  366.401f,  927.659f,
      736.222f,  -633.684f, -329.927f, -430.155f, -633.062f, -146.548f,
      -1324.28f, -1349.36f, -242.675f, 117.448f,  -801.723f, -391.514f,
      -404.818f, 454.16f,   515.48f,   -133.031f, 69.293f,   590.096f,
      -1434.69f, -1070.89f, 307.074f,  400.525f,  -316.12f,  -587.125f,
      -161.056f, 800.363f,  -96.4708f, 748.706f,  868.174f,  -447.938f,
      112.737f,  1127.2f,   47.4355f,  677.72f,   593.186f,  -336.4f,
      551.362f,  397.823f,  78.3979f,  -715.398f, 405.969f,  404.256f,
      246.019f,  -8.42969f, 131.365f,  -648.051f};

  const size_t expected_size = 1;
  EXPECT_EQ(outputs.size(), expected_size);

  auto output = outputs.front();
  ConvertFP16toFP32(output);
  auto outputs_size = 1;
  for (auto dim : output.shape) {
    outputs_size *= dim;
  }
  float* fp32_data = reinterpret_cast<float*>(output.data.data());

  for (size_t j = 0; j < outputs_size; j += 10) {
    EXPECT_NEAR(
        (fp32_data[j] - truth_values[j / 10]) / truth_values[j / 10], 0., 9e-2);
  }
}

}  // namespace inference
}  // namespace paddle
