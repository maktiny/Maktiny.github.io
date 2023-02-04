
#子目录中的CMakeLists.txt文件

# 查找当前目录下的所有源文件
# 并将名称保存到 DIR_SRCS 变量
aux_source_directory(. DIR_LIB_SRCS)

#将子目录中的程序编译成静态库
add_library(mathfunction ${DIR_LIB_SRCS})

