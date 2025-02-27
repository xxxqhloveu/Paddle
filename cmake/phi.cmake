# Copyright (c) 2021 PaddlePaddle Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function(generate_unify_header DIR_NAME)
  set(options "")
  set(oneValueArgs HEADER_NAME SKIP_SUFFIX)
  set(multiValueArgs EXCLUDES)
  cmake_parse_arguments(generate_unify_header "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # get header name and suffix
  set(header_name "${DIR_NAME}")
  list(LENGTH generate_unify_header_HEADER_NAME
       generate_unify_header_HEADER_NAME_len)
  if(${generate_unify_header_HEADER_NAME_len} GREATER 0)
    set(header_name "${generate_unify_header_HEADER_NAME}")
  endif()
  set(skip_suffix "")
  list(LENGTH generate_unify_header_SKIP_SUFFIX
       generate_unify_header_SKIP_SUFFIX_len)
  if(${generate_unify_header_SKIP_SUFFIX_len} GREATER 0)
    set(skip_suffix "${generate_unify_header_SKIP_SUFFIX}")
  endif()

  # exclude files
  list(LENGTH generate_unify_header_EXCLUDES generate_unify_header_EXCLUDES_len)

  # generate target header file
  set(header_file ${CMAKE_CURRENT_SOURCE_DIR}/include/${header_name}.h)
  file(
    WRITE ${header_file}
    "// Header file generated by paddle/phi/CMakeLists.txt for external users,\n// DO NOT edit or include it within paddle.\n\n#pragma once\n\n"
  )

  # get all top-level headers and write into header file
  file(GLOB HEADERS "${CMAKE_CURRENT_SOURCE_DIR}\/${DIR_NAME}\/*.h")
  foreach(header ${HEADERS})
    if(${generate_unify_header_EXCLUDES_len} GREATER 0)
      get_filename_component(header_file_name ${header} NAME)
      list(FIND generate_unify_header_EXCLUDES ${header_file_name} _index)
      if(NOT ${_index} EQUAL -1)
        continue()
      endif()
    endif()
    if("${skip_suffix}" STREQUAL "")
      string(REPLACE "${PADDLE_SOURCE_DIR}\/" "" header "${header}")
      file(APPEND ${header_file} "#include \"${header}\"\n")
    else()
      string(FIND "${header}" "${skip_suffix}.h" skip_suffix_found)
      if(${skip_suffix_found} EQUAL -1)
        string(REPLACE "${PADDLE_SOURCE_DIR}\/" "" header "${header}")
        file(APPEND ${header_file} "#include \"${header}\"\n")
      endif()
    endif()
  endforeach()
  if(DEFINED REDUCE_INFERENCE_LIB_SIZE)
    if(${kernel_name} MATCHES ".*_grad")
      continue()
    endif()
  endif()
  # append header into extension.h
  string(REPLACE "${PADDLE_SOURCE_DIR}\/" "" header_file "${header_file}")
  file(APPEND ${phi_extension_header_file} "#include \"${header_file}\"\n")
endfunction()

# call kernel_declare need to make sure whether the target of input exists
function(kernel_declare TARGET_LIST)
  # message("TARGET LIST ${TARGET_LIST}")
  foreach(kernel_path ${TARGET_LIST})
    # message("kernel path ${kernel_path}" )
    file(READ ${kernel_path} kernel_impl)
    string(
      REGEX
        MATCH
        "(PD_REGISTER_KERNEL|PD_REGISTER_KERNEL_FOR_ALL_DTYPE|PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE|PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE_EXCEPT_CUSTOM)\\([ \t\r\n]*[a-z0-9_]*,[[ \\\t\r\n\/]*[a-z0-9_]*]?[ \\\t\r\n]*[a-zA-Z_]*,[ \\\t\r\n]*[A-Z_]*"
        first_registry
        "${kernel_impl}")
    set(kernel_declare_id "")
    while(NOT first_registry STREQUAL "")
      string(REPLACE "${first_registry}" "" kernel_impl "${kernel_impl}")
      # some gpu kernel can run on cuda, but not support jetson, so we add this branch
      if(WITH_NV_JETSON)
        string(FIND "${first_registry}" "decode_jpeg" pos)
        if(pos GREATER 1)
          set(first_registry "")
        endif()
      endif()
      # fusion group kernel is not supported in windows and mac
      if(WIN32 OR APPLE)
        string(FIND "${first_registry}" "fusion_group" pos)
        if(pos GREATER 1)
          set(first_registry "")
        endif()
      endif()
      # some gpu kernel only can run on cuda, not support rocm, so we add this branch
      if(WITH_ROCM)
        string(FIND "${first_registry}" "cuda_only" pos)
        if(pos GREATER 1)
          set(first_registry "")
        endif()
      endif()

      if(NOT first_registry STREQUAL "")
        string(
          REGEX
            MATCH
            "(PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE_EXCEPT_CUSTOM)\\([ \t\r\n]*[a-z0-9_]*,[[ \\\t\r\n\/]*[a-z0-9_]*]?[ \\\t\r\n]*[a-zA-Z_]*,[ \\\t\r\n]*[A-Z_]*"
            is_all_backend
            "${first_registry}")
        if(NOT is_all_backend STREQUAL "")
          # parse the registerd kernel message
          string(
            REPLACE "PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE_EXCEPT_CUSTOM("
                    "" kernel_msg "${first_registry}")
        else()
          string(
            REGEX
              MATCH
              "(PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE)\\([ \t\r\n]*[a-z0-9_]*,[[ \\\t\r\n\/]*[a-z0-9_]*]?[ \\\t\r\n]*[a-zA-Z_]*,[ \\\t\r\n]*[A-Z_]*"
              is_all_backend
              "${first_registry}")

          # parse the registerd kernel message
          string(REPLACE "PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE(" ""
                         kernel_msg "${first_registry}")
        endif()
        string(REPLACE "PD_REGISTER_KERNEL(" "" kernel_msg "${kernel_msg}")
        string(REPLACE "PD_REGISTER_KERNEL_FOR_ALL_DTYPE(" "" kernel_msg
                       "${kernel_msg}")
        string(REPLACE "," ";" kernel_msg "${kernel_msg}")
        string(REGEX REPLACE "[ \\\t\r\n]+" "" kernel_msg "${kernel_msg}")
        string(REGEX REPLACE "//cuda_only" "" kernel_msg "${kernel_msg}")

        list(GET kernel_msg 0 kernel_name)
        if(NOT is_all_backend STREQUAL "")
          list(GET kernel_msg 1 kernel_layout)
          set(kernel_backend "CPU")
        else()
          list(GET kernel_msg 1 kernel_backend)
          list(GET kernel_msg 2 kernel_layout)
        endif()
        set(kernel_declare_id
            "${kernel_declare_id}PD_DECLARE_KERNEL(${kernel_name}, ${kernel_backend}, ${kernel_layout});"
        )
        if("${KERNEL_LIST}" STREQUAL "")
          set(first_registry "")
        else()
          string(
            REGEX
              MATCH
              "(PD_REGISTER_KERNEL|PD_REGISTER_KERNEL_FOR_ALL_DTYPE|PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE|PD_REGISTER_KERNEL_FOR_ALL_BACKEND_DTYPE_EXCEPT_CUSTOM)\\([ \t\r\n]*[a-z0-9_]*,[[ \\\t\r\n\/]*[a-z0-9_]*]?[ \\\t\r\n]*[a-zA-Z_]*,[ \\\t\r\n]*[A-Z_]*"
              first_registry
              "${kernel_impl}")
        endif()
      endif()
    endwhile()
    # append kernel declare into declarations.h
    if(NOT kernel_declare_id STREQUAL "")
      file(APPEND ${kernel_declare_file} "${kernel_declare_id}\n")
    endif()
  endforeach()
endfunction()

function(append_op_util_declare TARGET)
  file(READ ${TARGET} target_content)
  string(REGEX MATCH "(PD_REGISTER_ARG_MAPPING_FN)\\([ \t\r\n]*[a-z0-9_]*"
               util_registrar "${target_content}")
  if(NOT ${util_registrar} EQUAL "")
    string(REPLACE "PD_REGISTER_ARG_MAPPING_FN" "PD_DECLARE_ARG_MAPPING_FN"
                   util_declare "${util_registrar}")
    string(APPEND util_declare ");\n")
    file(APPEND ${op_utils_header} "${util_declare}")
  endif()
endfunction()

function(append_op_kernel_map_declare TARGET)
  file(READ ${TARGET} target_content)
  string(
    REGEX
      MATCH
      "(PD_REGISTER_BASE_KERNEL_NAME)\\([ \t\r\n]*[a-z0-9_]*,[ \\\t\r\n]*[a-z0-9_]*"
      kernel_mapping_registrar
      "${target_content}")
  if(NOT ${kernel_mapping_registrar} EQUAL "")
    string(REPLACE "PD_REGISTER_BASE_KERNEL_NAME" "PD_DECLARE_BASE_KERNEL_NAME"
                   kernel_mapping_declare "${kernel_mapping_registrar}")
    string(APPEND kernel_mapping_declare ");\n")
    file(APPEND ${op_utils_header} "${kernel_mapping_declare}")
  endif()
endfunction()

function(register_op_utils TARGET_NAME)
  set(utils_srcs)
  set(options "")
  set(oneValueArgs "")
  set(multiValueArgs EXCLUDES DEPS)
  cmake_parse_arguments(register_op_utils "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  file(GLOB SIGNATURES "${PADDLE_SOURCE_DIR}/paddle/phi/ops/compat/*_sig.cc")
  foreach(target ${SIGNATURES})
    append_op_util_declare(${target})
    append_op_kernel_map_declare(${target})
    list(APPEND utils_srcs ${target})
  endforeach()

  cc_library(
    ${TARGET_NAME}
    SRCS ${utils_srcs}
    DEPS ${register_op_utils_DEPS})
endfunction()

function(prune_declaration_h)
  set(kernel_list ${KERNEL_LIST})
  file(STRINGS ${kernel_declare_file} kernel_registry_list)

  file(WRITE ${kernel_declare_file_prune} "")
  file(APPEND ${kernel_declare_file_prune}
       "// Generated by the paddle/phi/kernels/CMakeLists.txt.  DO NOT EDIT!\n")
  file(APPEND ${kernel_declare_file_prune} "#pragma once\n")
  file(APPEND ${kernel_declare_file_prune}
       "#include \"paddle/phi/core/kernel_registry.h\"\n")

  set(kernel_declare_list_prune)
  foreach(kernel_registry IN LISTS kernel_registry_list)
    if(NOT "${kernel_registry}" EQUAL "")
      foreach(kernel_name IN LISTS kernel_list)
        string(FIND "${kernel_registry}" "(${kernel_name})" index1)
        string(FIND "${kernel_registry}" "(${kernel_name}," index2)
        if((NOT ${index1} EQUAL "-1") OR (NOT ${index2} EQUAL "-1"))
          string(
            REGEX
              MATCH
              "PD_DECLARE_KERNEL\\([a-z0-9_]*, [[a-z0-9_]*]?[a-zA-Z_]*, [A-Z_]*\\)"
              first_registry
              "${kernel_registry}")
          list(APPEND kernel_declare_list_prune "${first_registry}")
        endif()
      endforeach()
    endif()
  endforeach()

  list(REMOVE_DUPLICATES kernel_declare_list_prune)
  foreach(kernel_declare_prune IN LISTS kernel_declare_list_prune)
    file(APPEND ${kernel_declare_file_prune} "${kernel_declare_prune};\n")
  endforeach()

  file(WRITE ${kernel_declare_file} "")
  file(STRINGS ${kernel_declare_file_prune} kernel_registry_list_tmp)
  foreach(kernel_registry IN LISTS kernel_registry_list_tmp)
    if(NOT ${kernel_registry} EQUAL "")
      file(APPEND ${kernel_declare_file} "${kernel_registry}\n")
    endif()
  endforeach()
endfunction()

function(collect_srcs SRC_GROUP)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs "SRCS")
  cmake_parse_arguments(prefix "" "" "${multiValueArgs}" ${ARGN})
  foreach(src ${prefix_SRCS})
    set(${SRC_GROUP}
        "${${SRC_GROUP}};${CMAKE_CURRENT_SOURCE_DIR}/${src}"
        CACHE INTERNAL "")
  endforeach()
endfunction()

function(collect_generated_srcs SRC_GROUP)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs "SRCS")
  cmake_parse_arguments(prefix "" "" "${multiValueArgs}" ${ARGN})
  foreach(src ${prefix_SRCS})
    set(${SRC_GROUP}
        "${${SRC_GROUP}};${src}"
        CACHE INTERNAL "")
  endforeach()
endfunction()
