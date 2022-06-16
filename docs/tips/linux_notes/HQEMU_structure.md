HQEMU的代码框架

1. 在QEMU的main()函数中初始化LLVM的环境

   ```c
                                                 main()<QEMU>
                                                    |
                                                llvm_init()
                                                     |
                                                CreateLLVMEnv()//开始初始化LLVMEnv变量（调用LLVMEnv()构造函数）
                                                     |
                                                  LLVMEnv()//创建一个TraceCache和Translator
                                                     |
                                                  CreateTranslator()//调用translator的构造函数和根据translator的数量初始化线程
                                                     |
                      -----------------------------------------------------------------------
                      |                                                                  |
                 StartThread()                                                     LLVMTranslator()
                     |                                                                   |
                     |                                                             InitializeModule();
                     |                                                             InitializeType();//初始化IRFactory()的数据
       		     |								   InitializeTarget();//获取CPUArchState()的数据
       		     | 							            InitializeHelpers();
       		     |							            InitializeDisasm();//使用LLVM的提供的MCdisassembler反汇编器类初始化一个反汇编器
                 WorkerFunc()/*让线程去执行该函数*/                              IRFactory()//translator最重要的数据结构
   ```

