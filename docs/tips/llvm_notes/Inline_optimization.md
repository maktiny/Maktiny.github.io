## LLVM的函数内联优化

### 编译时的内联控制
1. 在对源代码进行编译的时候，我们可以通过编译选项来控制编译器的内联行为，包括
* 内联的等级(normal inlining, aggressive inlining, inlinehint inlining, etc.),
* 内联的代价评估和阀数(inline-threshold, etc.)，
* 内联的范围(Module Scope, program scope with LTO/ThinLTO), profile guided (PGO, AutoFDO, etc.)

 2. 编译代码的过程中可以通过命令行参数指定编译参数，clang中和inline相关的命令行参数主要有如下几个
 ```c

 -fno-inline or -fno-inline-function 
 -finline-functions
 -finline-hint-functions
//上面的编译参数会转化为下面的编译选项
 -Ox(-O0, -O1, -O2, -O3, -Oz, -Os) 
 如上的命令行参数，LLVM会通过ParseCodeGenArgs处理过程，转换为代码生成时候的编译选项CodeGenOptions.inlining

```
### 开发者可设置的函数属性
1. 除了通过命令行参数设置全局的属性，对每个函数本身，我们可以通过function attributes来设置其属性，clang提供了如下主要的inlining相关属性
```c
inline
__attributes__((always_inline))
__attributes__((noinline))
```
2. LLVM通过SetLLVMFunctionAttributesForDefinition来处理语言层面的inlining属性，转换为代码生成函数的编译期代码生成属性
![2022-06-17 15-45-10 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h3baeibcsrj30iq0bdq4k.jpg)




### inliner内联器
1. 真正的内联是在中端生成LLVM IR的时候实现的
2. LLVM完成AST生成等Frontend的任务后，会进入代码生成阶段，该过程的入口是 clang::EmitBackendOutput @llvm-project/clang/lib/CodeGen/BackendUtil.cpp
3. 该入口函数主要的工作是通过一个EmitAssemblyHelper代理执行代码生成工作，LLVM的分析、优化和代码生成等过程均通过Pass Pipeline进行管理,
   代理首先创建所有相关的pass，并进行调度执行(PassManager::run)
4. 根据优先级的不同设置不同的inline 优化pass:当优化等级"<=1"创建AlwaysInliner, 当采用更高优化等级的时候则创建SimpleInliner.

```c
                     //LegacyInlinerBase类
                     //PassManager进行调度的时候，每个Inliner会执行对应的 "runOnSCC(CallGraphSCC &SCC)"虚函数
                                     runOnSCC()
                                       |
                                    inlineCalls()
                                       |
                                  inlineCallsImpl()
                                      |
                                      |
                                      |
                                      |-----------shouldInline()计算内联代价
                                      |
                                      |-----------inlineCallIfPossible()
                                                      |
                                                  InlineFunction()//真正进行内联处理的函数
```

### 内联开销的计算
1.对函数内联Cost计算。这些评估主要从内联的代码膨胀，执行开销等维度做出，在LLVM中通过InlineCost来作为Cost计算的抽象描述 


































