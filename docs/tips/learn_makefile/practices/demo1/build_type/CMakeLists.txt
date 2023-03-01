cmake_minimum_required(VERSION 3.0)

#选择编译类型是Debug或者Release类型的
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
	message("Setting build type to 'debug' as none was special")
	set(CMAKE_BUILD_TYPE RealWithDebInfo CACHE STRING "Choose the type of build" FORCE)
	set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS "Debug" "Release" "MinSizeRel" "RelWithDebInfo")
endif()
#设置使用C编译器
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DEX3" CACHE STRING "Set c Compiler Flags" FORCE)

project(build_type)



#引入编译标准c++11或者其他
include(CheckCXXCompilerFlag)
CHECK_CXX_COMPILER_FLAG("-std=c++11" COMPILER_SUPPORTS_CXX11)
CHECK_CXX_COMPILER_FLAG("-std=c++0x" COMPILER_SUPPORTS_CXX0X)

#检查flags的设置情况
if(COMPILER_SUPPORTS_CXX11)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
elseif(COMPILER_SUPPORTS_CXX0X)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++0x")
else()
	message(STATUS "the compiler ${CMAKE_CXX_COMPILER} has no c++11 support")
endif()

add_executable(${PROJECT_NAME} main.cpp)

target_compile_features(${PROJECT_NAME} PUBLIC cxx_auto_type)

message("List of compile feature: ${CMAKE_CXX_COMPILERFEATURES}")



target_compile_definitions(${PROJECT_NAME} 
	PRIVATE EX3
	)
