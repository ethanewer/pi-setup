cmake_minimum_required(VERSION 3.16)
project(saltern LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(USE_GPU "Build the CUDA training path (saltern_gpu)" ON)

add_subdirectory(core)

if(USE_GPU)
  # The CUDA path. Requires a real CUDA toolkit at configure time.
  include(${CMAKE_CURRENT_LIST_DIR}/gpu/enable_gpu.cmake)
  add_executable(saltern_gpu gpu/train_gpu.cpp)
  target_link_libraries(saltern_gpu PRIVATE saltern_core)
else()
  # The CPU-only training binary.
  add_executable(saltern_cpu cpu/train_cpu.cpp)
  target_link_libraries(saltern_cpu PRIVATE saltern_core)
endif()
