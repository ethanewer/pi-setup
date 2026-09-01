cmake_minimum_required(VERSION 3.10)
project(choron LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(choron
  src/main.cpp
  src/digit.cpp
)