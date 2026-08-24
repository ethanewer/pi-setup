cmake_minimum_required(VERSION 3.10)

# Project definition - wrong name
project(WrongProject)

# Missing utils.c source file
add_executable(my_app src/main.c)

# Incorrect include path
target_include_directories(my_app PRIVATE ../include)

# Missing C standard specification