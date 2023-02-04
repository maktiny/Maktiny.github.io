#命令大小写无关
cmake_minimum_required(VERSION 3.0)             #设置最低的cmake版本
project(cmake)                                  #该项目生成的二进制(最终可执行文件的名称)
SET(EXECUTABLE_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/build)  #设置可执行文件的输出目录 PROJECT_SOURCE_DIR项目根目录，也就是CmakeLists.txt目录的绝对路径。

# 设置运行时目标文件（exe、dll）的输出位置
#set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# 设置存档目标文件（lib、a）的输出位置
#set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

#添加子目录
add_subdirectory(src)

#生成指定目标
add_executable(${PROJECT_NAME} main.c)  #add_executable的第一个参数表示可执行程序的名字

#添加链接库
target_link_libraries(${PROJECT_NAME} mathfunction)
