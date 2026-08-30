add_library(saltern_core STATIC model.cpp data.cpp)
target_include_directories(saltern_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_features(saltern_core PUBLIC cxx_std_17)
