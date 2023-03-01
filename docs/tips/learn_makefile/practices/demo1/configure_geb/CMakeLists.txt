cmake_minimum_required(VERSION 3.5)

project(configure_example)

#设置版本号
set(configure_example_VERSION_MAJOR 0)
set(configure_example_VERSION_MINOR 2)
set(configure_example_VERSION_PATCH 1)
set(configure_example_VERSION "${configure_example_VERSION_MAJOR}.${configure_example_VERSION_MINOR}.${configure_example_VERSION_PATCH}")

#使用两种${} 和@@  传递参数
configure_file(ver.h.in ${PROJECT_SOURCE_DIR}/ver.h) #生成的ver.h放在PROJECT_SOURCE_DIR
configure_file(path.h.in ${PROJECT_SOURCE_DIR}/path.h @ONLY)


add_executable(${PROJECT_NAME} main.cpp)


