// Copyright 2020 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef LIB_PROCESS_WRAPPER_SYSTEM_H_
#define LIB_PROCESS_WRAPPER_SYSTEM_H_

#include <string>
#include <vector>

#if defined(_WIN32) && defined(UNICODE)
#define PW_WIN_UNICODE
#endif  // defined(_WIN32) && defined(UNICODE)

#if defined(PW_WIN_UNICODE)
#define PW_SYS_STR(str) L##str
#define PW_MAIN wmain
#else
#define PW_SYS_STR(str) str
#define PW_MAIN main
#endif

namespace process_wrapper {

class System {
 public:
#if defined(PW_WIN_UNICODE)
  using StrType = std::wstring;
#else
  using StrType = std::string;
#endif  // defined(PW_WIN_UNICODE)

  using StrVecType = std::vector<StrType>;
  using Arguments = StrVecType;
  using EnvironmentBlock = StrVecType;

 public:
  // Gets the working directory of the current process
  static StrType GetWorkingDirectory();

  // Simple function to execute a process that inherits all the current
  // process handles.
  // Even if the function doesn't modify global state it is not reentrant
  // It is meant to be called once during the lifetime of the parent process
  static int Exec(const StrType& executable, const Arguments& arguments,
                  const EnvironmentBlock& environment_block,
                  const StrType& stdout_file, const StrType& stderr_file);
};

}  // namespace process_wrapper

#endif  // LIB_PROCESS_WRAPPER_SYSTEM_H_
