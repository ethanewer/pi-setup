cmake_minimum_required(VERSION 3.10)
project(transwc C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Graphical X11 frontend.  ON requires the X11 development headers; when OFF
# only the headless engine entry point is built and nothing links libX11.
option(ENABLE_GUI "Build the X11 graphical frontend" ON)

add_library(core STATIC src/core.c)

if(ENABLE_GUI)
  find_package(X11 REQUIRED)
  add_executable(transwc src/gui_x.c)
  target_link_libraries(transwc PRIVATE core X11)
else()
  add_executable(transwc src/head_main.c)
  target_link_libraries(transwc PRIVATE core)
endif()