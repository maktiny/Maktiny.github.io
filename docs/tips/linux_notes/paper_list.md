## Dynamic Binary translator

### Software Profiling for Hot Path Prediction:Less is More

```
The key idea is to focus the profiling effort on
only the potential starting points of hot paths. Once a path starting
point has become hot a prediction is made by speculatively
selecting the Next Executing Tail (NET) as the hot path.
```
* 只关注热路径的头结点，只要头结点变热，头结点之后的路径即为热路径
* 只需要在头节点进行代码插桩和执行计数，达到阈值之后触发helper函数处理热路径


### Dynamo: A Transparent Dynamic Optimization System
1. 使用NET(MRET)算法识别热路径，达到阈值之后使用中断处理热路径
2. 在热路径合并的时候的优化:直接跳转移除 ,call return也可以移除, 把间接跳转转化为条件跳转，合成fragment(superblock),消除load/store等冗余指令。
,然后在把fragment link起来放到cache中，cache的管理是，当fragment大量产生的时候直接flush  掉cache.

### Improving Dynamically-Generated Code Performance on Dynamic Binary Translators 2005
1. 使用NET算法识别热路径
2. 在热路径中消除冗余的跳转分支,生成更好的host code
3. 提出了一种算法，提高code cache中的翻译好的代码的重用，提高翻译器性能。

### Optimising Hot Paths in a Dynamic Binary Translator 2001
1. 使用 edge weight profile 算法识别热路径
2. edge weight profile算法：维护两个TB转移的边，把两个TB转移次数赋值边的权重，当权重达到阈值，触发设置号的触发器，来收集边链接的TB作为热路径
3. 算法的改进版：还可以顺着找到的edge(权重达到阈值的边)的TB link往下寻找（比较edge的权重是否达到阈值）TB块，找到更多的热点块，连接成热路径
4. 优化：根据收集到的信息重新生成热路径上的TB，然后改变TB在hot cache中的布局（类似于把TB合并到一起生成超级块，把直接跳转消除掉），消除一些不必要的控制流转移。

### Processor-Tracing Guided Region Formation in Dynamic Binary Translation 2018



### Trace Execution Automata in Dynamic Binary Translation
1. 根据profile信息，使用有限状态机来记录追踪到的trace,模拟trace的执行流程


#### HotpathVM: An Effective JIT Compiler for Resource-constrained Devices
1. 也是使用NET算法识别热路径，
2. 在路径合并的时候处理一些边角情况，入嵌套loop,同一个header多个热路径的时候使用第二路径，当一个路径退出的时候，使用第二个路径，


#### Design and Implementation of a Lightweight Dynamic Optimization System
1. 使用硬件计数器BTB(Branch Trace Buffer)采样，当一个TB到达阈值的时候，收集以他为头结点的路径


#### Improving Region Selection in Dynamic Optimization Systems. 2005
1. 针对NET算法的缺点：1). trace sperate   2). code duplicate 提出了LEI算法
2. NET向后跳转分支判断成环，识别成两条路径，LEI使用一个hash表来缓存TB地址，当跳转的TB地址在hash表中的时候，才识别是环，提高识别的精确度
3. 至于code duplicate问题是所有识别热路径算法的缺点， LEI使用trace combinations,路径合并（类似于TB合并），可以消除一些重复代码，比如退出代码块(类似tb_exit)



#### 动态二进制翻译中的热路径优化 2008 上交大
1. 介绍了CrossBit动态二进制翻译中热路径的识别以及超级块的优化
2. 热路径识别：使用NET算法，对中间码进行插桩收集信息，生成超级块
3. 超级块的优化：1).(块间优化)条件分支跳转的转码(比如把bne 变成 be)  2).（块内优化）删除冗余的load/store等冗余指令。

#### 动态二进制翻译中基于 profile 的优化算法研究 2008 上交大
基于路径的热路径算法：
1. 类似NET算法（头块的识别使用NET的思想，p ( A , 7 ) ＝ {A , 0110010 }），只是他使用路径编码的方式把一条路径的每一个基本块都确定了
NET算法只知道头结点，后续的热点块需要另外确定

2. 他是基于IR实现的，在中间层可以容易的实现对路径编码，如果只有后端，怎实现路径编码，每一个TB都切换到qemu去进行编码？开销太大


#### Improving the Performance of Trace-based Systems by False Loop Filtering 2011
1. cyclic-path-based repetition detector,改进该算法，使其能够筛选出false loop，改善JIT的编译效率

#### 二进制翻译中基于数据流和控制流分析的代码优化方法-----中科院博士论文
1. 静态数据流分析方法
* 抽象出数据流图DFG-IR 
* 根据DFG进行活性分析，冗余访存消除，无效分支消除，热点数据(比如env)等数据分配特定的寄存器存储(类似寄存器直接映射)

2. 动态控制流的superblock的优化
* 根据插桩获取的profing信息，提取热点代码块hot TB, 生成superblock
* 基于延迟槽对函数调用和返回指令的翻译进行优化
* 使用多线程重新翻译hot TB，根据CFS控制流图对hot TB进行重排，改善热点代码的空间局部性，减少cache missing rate
* 基于控制流对冗余代码进行消除
* 生成superblock的时候必须保每个TB的exit_tb,应为SMC自修改代码无效TB或者unlink的时候需要退出到host态(此时code cache中只有优化后的superblock,原来的TB无效掉了)

#### alto: a link-time optimizer for the Compaq Alpha
1. 连接时的优化器：连接时可以知道变量的地址，最后的代码布局等信息，可以知道的信息比链接之前更多，优化的机会更多
* 常量传播，存活性分析，不可达代码消除，常量值计算，消除不必须的访存，函数内联，优化代码布局，指令调度


#### BOLT: A Practical Binary Optimizer for Data Centers and Beyond ---后连接优化器
1. 针对数据中心这样大规模程序的优化(基本块 和 函数的重排) --基于LLVM的优化，优化pass,代码开源，提交llvm中:https://github.com/llvm/llvm-project/blob/main/bolt/docs/OptimizingClang.md
2. 静态优化器offline,
3. 利用perf的ptrace绑定目标进程，然后对(Intel)LBR最近分支记录(Last branch record)采样，获取profile信息，


#### OCOLOS: Online COde Layout OptimizationS----把bolt改成online的优化器
1. 为了提高L1 cache和iTLB的命中率，充分利用程序的局部性，提出了basic block基本块和function函数的重排,
2. hot-cold基本块和函数中的hot-cold基本块都是分开存储的
3. 利用perf的ptrace绑定目标进程，然后对(Intel)LBR最近分支记录(Last branch record)采样，获取profile信息，
4. 根据采样信息区分hot和cold基本块，然后利用ptrace对function调用进行拦截，获取function的信息
5. 利用LLVM的pass对hot基本块进行优化，然后重排， 
6. function中的hot基本块也进行重排， 函数重排：被调函数紧挨着调用函数之后(递归重排)，难点由于函数地址改变，需要修改函数的返回地址以及函数调用栈
7. 采样开销大，但是对于数据中心，大型数据库系统(MySQL性能提升1.4倍)这样的应用场景性能提升明细


#### Verified Peephole Optimization for CompCert 
* 附录有对应的窥孔优化的pattern
