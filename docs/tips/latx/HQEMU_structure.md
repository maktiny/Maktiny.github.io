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
                     |                                                             InitializeType();//初始化IRFactory()的数据类型
       		     |							            InitializeTarget();//获取CPUArchState()的数据
       		     | 							            InitializeHelpers();
       		     |							            InitializeDisasm();//初始化LLVM提供的MCDisassembler反汇编器                                                                                 汇编器（MCDisassembler LLVM中的反汇编器）
                 WorkerFunc()/*让线程去执行该函数*/                                   IRFactory()//translator最重要的数据结构,构建QEMU的TCG opcode
                     |//该函数有一个死循环，当队列不为空的时候
                     |//不停的从队列头部取出一个Hot path
                     |//放入GenTrace(),生成Trace
       -----------------------------------------
        |                                     |
      optimization_init()                   GenTrace()-----
       |-----------------CPUOptimization()//初始化间接分支|缓存，指令TLB，跨页块链接等
      CreateTracer()//调用构造函数NETTrace()，创建NET对象 |并注册该线程(也就是初始化监视对象，对线程的运行情况做监视)
                                                          |
                                                          |
                                                      
                                          GenTrace()//现在HQEMU在GenTrace就挂掉了(也就是LLVM后端没有拉起来)
                                             |--- TraceBuilder Builder(IF, Opt);//构建一个Tracebuilder类实例，初始翻译之前的数据结构------------------------------
                                             |                                                                                                                    |
                                             |                                                                                                                    |
                              --------------------------------------------------                                                                            CreateSession()
                             |                                                  |                                                                                 |
                      ConvertToTCGIR()                                  ConvertToLLVMIR()                                                                      CreateJIT()//调用MCJITcreate()方法生成一个JIT或MCJIT引擎实例
                           |                                                   |                                                                               //用来将LLVM IR生成机器码，并存放在内存中。(此时并没有进行编译)
                    gen_intermediate_code()                             (IF->*OpcFunc[op->opc])(args);//使用宏调用指令的翻译函数                                   |
                    //调用QEMU的前端函数生成TCG IR                      //比如TCG IR的mov_i32指令会使用宏拼接形成TCG IR --> LLVM IR的op_mov_i32()                  |
                          |                                                                                                                                       ---Compile()是实现编译的调用接口函数
                    translator_loop()                                                                                                                                |
                    //循环翻译TB中的指令                                                                                                                          Optimize() //在编译之前，通过调用该函数把各种pass
                         |                                                                                                                                        //加入到pass manager中，并调用pass 优化LLVM IR。
                   tcg_gen_hotpatch()                                                                                                                                |
                   //HQEMU翻译hotpath---> TCG IR的开始函数                                                                                                     getPointerToFunction()//调用该函数把LLVM IR 作为参数传入，启动JIT编译
                        |                                                                                                                                      //翻译出来的机器码放在内存，返回内存地址。
                   tcg_gen_op2() 
                   //-->tcg_emit_op()生成TCG IR的操作码，然后把操作数填进去   









```

   

