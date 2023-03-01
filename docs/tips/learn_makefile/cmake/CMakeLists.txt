#命令大小写无关
cmake_minimum_required(VERSION 3.0)             #设置最低的cmake版本
project(cmake)                                  #该项目生成的二进制(最终可执行文件的名称)

#设置两个参数作为版本号

set(cmake_VERSION_MAJOR 1)
set(cmake_VERSION_MINOR 0)


SET(EXECUTABLE_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/build)  #设置可执行文件的输出目录 PROJECT_SOURCE_DIR项目根目录，也就是CmakeLists.txt目录的绝对路径。

# 设置运行时目标文件（exe、dll）的输出位置
#set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# 设置存档目标文件（lib、a）的输出位置
#set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

#加入配置头文件，用于处理CMake对源码的设置
configure_file(
	"${PROJECT_SOURCE_DIR}/config.h.in"
	"${PROJECT_SOURCE_DIR}/config.h"
	)
#添加选项是否使用自己的mathfunction库  默认使用
option(USE_MYFUNCTION "Use my math function" ON) 

#是否加入自己的库
if (USE_MYFUNCTION)
	#指定所有目标的头文件路径。也可以使用target_include_directories()
	include_directories("${PROJECT_SOURCE_DIR}/src")
#include_directories(header-dir) 是一个全局包含，向下传递
#就是说如果某个目录的 CMakeLists.txt 中使用了该指令，其下所有的子目录默认也包含了header-dir 目录
	#添加子目录
	add_subdirectory(src)
	set(EXTRA_LIBS ${EXTRA_LIBS}  mathfunction) #set用来设置参数
endif()

#生成指定目标
add_executable(${PROJECT_NAME} main.c)  #add_executable的第一个参数表示可执行程序的名字

#添加链接库
target_link_libraries(${PROJECT_NAME} ${EXTRA_LIBS})
#target_include_directories()：指定目标包含的头文件路径。
#target_link_libraries()：指定目标链接的库。
#target_compile_options()：指定目标的编译选项。
#目标 由 add_library() 或 add_executable() 生成。
#关键字 PUBLIC PRIVATE INTERFACE三个关键字指定目标文件依赖项的使用范围
#每一个目录都是一个模块，目录内部应将对外和对内的头文件进行区分，由模块的调用者决定模块是否被传递（PRIVATE，INTERFACE，PUBLIC）。

#使用cpack构建安装包
include(InstallRequiredSystemLibraries)       #导入模块InstallRequiredSystemLibraries
#set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/License.txt") #设置版权信息
set(CPACK_PACKAGE_VERSION_MAJOR "${cmake_VERSION_MAJOR}")  #设置版本号信息
set(CPACK_PACKAGE_VERSION_MINOR "${cmake_VERSION_MINOR}")
include(CPack)  #导入cpack模块



# cmake默认生成Makefiles ,但是也支持Ninja编译构建，使用cmake .. -G Ninja
