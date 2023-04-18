1. 先运行LLVM中的bc.sh脚本，生成llvm_helper_.bc,可能报路径错，在脚本中把相关文件的路径加进去 如-I../include/tcg

2. 把生成的llvm_helper_.bc放在~/.hqemu/llvm_helper_.bc。 注意先创建目录 mkdir ~/.hqemu
