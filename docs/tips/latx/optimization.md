### 窥孔优化


#### 现在实施方案的改进
1. 把enable_hot_profile放在env这个数据结构中，而不是TRANSLATE_BLOCK中，这样就可以采样一个TRACE，而不是一个TB,减少每个TB翻译时候的enable_hot_profile维护指令

2. 把TB的rb_count初始化为50,每次TB执行的时候tb_count--, 这样insert_collectpath_code中减少一条指令，少了加载阈值threshold的指令，tb_count直接与zero比较  “已经处理”

3. 由于上下文切换指令是公共的指令(store和load regs)，不需要每个TB的都进行插入，可以跳转到一个函数执行上下文的切换操作，减少指令膨胀,模仿generate_native_jmp_glue

4. 现在的无效TB需要断开TB link,效率很低，我们可以使新旧TB同时存在于code cache中，在旧TB的头部插入jmp指令，然后跳转到新的TB,这样就不用unlink了 "已经处理"

5. 现在的helper机制性能太低了，换成使用汇编指令处理的helper机制。

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
4. 模式扩展(extension_mode 消除之后，就是每个需要高位清零的地方插入一条bstrpick.d)
* 有些x86指令可能不需要高位清零，在重新翻译的时候可以做一些判断，有可能消除一些bstrpick的操作

5.TB间接跳转和直接跳转的优化必须保守(也就是exit_tb必须保留，两个出口必须维护)， 应为就算组合成superblock之后，各个TB也可能无效(或者自修改)，
此时需要利用exit_tb退出到host态进行处理，所以exit_tb必须保留


6.现在的多线程框架是否合理

```c
                  一个执行线程：多个优化线程造成加锁(一个优化线程?) //////////////或者翻译的时候使用多线程翻译(主线程优化，从线程翻译)
```

7. 翻译后形成的LoongArch汇编指令是IR2_INST形式组织的， 一个TB的所有IR2_INST存放在TRANSLATION_DATA的一个ir2_inst_array的数组中
需要消除指令的时候，对ir2_inst_array数组进行标记(置空?) ，在汇编的时候进行判断即可消除指令。(必须在label_dispose之前消除，
因为之后开始计算指令在code cache中的地址。),所有的优化可以放在tr_ir2_optimize()


8. 可以在tr_ir2_generate()中将TRANSLATION_DATA数据结构保存起来， TRANSLATION_BLOCK是维护code Cache中二进制码的数据结构，
根据TRANSLATION_DATA构建控制流图。然后进行接下来的优化。

9. 现在的上下文切换需要保存和恢复大量的寄存器，我们可以追踪寄存器的修改情况，如果没有被修改，就不用保存和恢复，可以删除两条指令。
