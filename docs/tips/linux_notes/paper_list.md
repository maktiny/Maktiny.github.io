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












### Improving the Performance of Trace-based Systems by False Loop Filtering 2011
1. cyclic-path-based repetition detector,改进该算法，使其能够筛选出false loop，改善JIT的编译效率
