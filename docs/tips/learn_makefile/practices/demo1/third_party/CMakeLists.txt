cmake_minimum_required(VERSION 3.5)

project(third_party)

#查找第三方库
find_package(Boost REQUIRED COMPONENTS filesystem system)

if(Boost_FOUND) 
	message("boost found")
else()
	message(FATAL_ERROR "cann't find boost ")
endif()

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

target_link_libraries(${PROJECT_NAME} 
	PRIVATE
	Boost::filesystem
	)
