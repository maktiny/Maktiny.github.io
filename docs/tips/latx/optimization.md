### 窥孔优化


#### 现在实施方案的改进
1. 把enable_hot_profile放在env这个数据结构中，而不是TRANSLATE_BLOCK中，这样就可以采样一个TRACE，而不是一个TB,减少每个TB翻译时候的enable_hot_profile维护指令
2. 把TB的rb_count初始化为50,每次TB执行的时候tb_count--, 这样insert_collectpath_code中减少一条指令，少了加载阈值threshold的指令，tb_count直接与zero比较
3. 由于上下文切换指令是公共的指令(store和load regs)，不需要每个TB的都进行插入，可以跳转到一个函数执行上下文的切换操作，减少指令膨胀


#### 优化的点
1.
```
IR1 :
IR1[2] 0x402fda:	mov		dword ptr [rip + 0x2cc268], eax
IR1[3] 0x402fe0:	mov		dword ptr [rip + 0x2cc266], ebx
IR1[4] 0x402fe6:	mov		dword ptr [rip + 0x2cc264], ecx
IR1[5] 0x402fec:	mov		dword ptr [rip + 0x2cc262], edx

IR2:
[71, 2] -------   4206554
lu12i.w   [31mitmp0[m,0x6cf    //加载rip的地址可以优化掉,rip没有直接寄存器映射
ori       [31mitmp0[m,[31mitmp0[m,0x248
st.w      $s0,[31mitmp0[m,0

```

2. 消除一些冗余的load/store操作，
* 先看看gcc的数据流分析的实现，先构建数据流分析的数据结构


3. 消除基本块冗余的EFLAG计算：
* 现在的EFLAG是基于每条指令来进行计算的，如果没有EFLAG的改变，不需要写到内存中,如果改变了EFLAG，则写入到内存
* 识别出hot TB之后， 可以基于整个TB 或者 多个hot TB（也就是一个trace）进行EFLAG的计算(把冗余的EFLAG计算消除掉)
```
EFLAG的回写到内存以整个TB为单位，如果在TB中间对EFLAG修改过并且后继指令也需要使用EFLAG的值，则插入计算，写回EFALGE的操作。
```
