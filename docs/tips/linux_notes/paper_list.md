## Dynimic Binary translator

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
