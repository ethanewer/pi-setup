#include <iostream>
#include "project_config.h"

#ifdef ENABLE_LOGGING
#define LOG(msg) std::cout << "[LOG] " << msg << std::endl
#else
#define LOG(msg)
#endif

int main() {
    LOG("Starting " PROJECT_ID);
    
    std::cout << "Project: " << PROJECT_ID << std::endl;
    std::cout << "Version: " << VERSION_MAJOR << "." << VERSION_MINOR << std::endl;
    std::cout << "Max threads: " << MAX_THREADS << std::endl;
    std::cout << "Build type: " << BUILD_TYPE << std::endl;
    std::cout << "Build time: " << BUILD_TIMESTAMP << std::endl;
    
    #ifdef DEBUG
    std::cout << "Debug build" << std::endl;
    #endif
    
    return 0;
}