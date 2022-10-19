#### peephole optimization

##### pattern 1 : push/pop的消除
* 直接对st.d和addi.d的模式进行识别，有几个st.d和addi.d的模式对进行计数n，

```
ir2:
push		r15
push		r14
push		r13
push		r12

ir1:
[12, 4] -------   5175814
st.d      $t7,$s4,-8
addi.d    $s4,$s4,-8
[15, 5] -------   5175816
st.d      $t6,$s4,-8
addi.d    $s4,$s4,-8

## 一次遍历得到n，然后offset = n * 4;
在最后一个push的时候才进行更新栈指针esp(s4)，addi.d    $s4,$s4,-offset



```
##### pattern 2: 当目的寄存器是$zero的时候，可以消除该指令   (Done)

```c
IR1 :     call 0x42c8f0

IR2：
    lu12i.w itmp1,0x405
	ori itmp1,itmp1,0xf0d
	st.d itmp1,$s4,-8
	addi.d $s4,$s4,-8
	and $zero,$zero,$zero //可以消除


IR1:  lea             rcx, [rsp + 0xc] //当reg为64位寄存器的时候可以优化掉 or指令

IR2:
addi.d    $s1,$s4,12
or        $s1,$s1,$zero  //可以消除




IR1:   nop     word ptr [rax + rax]

IR2:   andi      $zero,$zero,0x0 //可以消除

```

##### pattern 3: 不是常见的模式,不具有一般性

```c
IR1；
    mov             dword ptr [rsp + 0x18], eax
    mov             edx, dword ptr [rsp + 0x18]

IR2:
st.w      $s0,$s4,24
[11, 3] -------   4509923
ld.wu     $s2,$s4,24

```

##### pattern 4:
```asm
IR1 :
  
```


## IR1层面的指令融合
##### pattern 3: IR1层面的消除，cmp-cmovcc  和 test-cmovcc

```c
IR1:
	cmp     rax, -1
   	cmove   rax, rdx

 IR2:
  [5, 2] -------   4886494
  169390 ld.b      ^[[31mitmp0^[[m,$s4,79
  169391 x86sub.b  ^[[31mitmp0^[[m,$zero
  169392 [8, 3] -------   4886499
  169393 setx86j   ^[[31mitmp0^[[m,5     //cmp_cmovcc联合翻译， setx86j指令可以消除
  169394 masknez   ^[[32mitmp1^[[m,$t8,^[[31mitmp0^[[m
  169395 maskeqz   ^[[33mitmp2^[[m,$s0,^[[31mitmp0^[[m
  169396 or        $t8,^[[32mitmp1^[[m,^[[33mitmp2^[[m

```

* CMP    A    B    unsigned      cmp-cmovcc

  ```c
  CMP   A       B   unsigned
   >  cmova   cf = 0 zf = 0      sltu rd  B  A  | B < A
   >= cmovae  cf = 0 zf = 0/1    sltu rd  A  B  | A < B  使用cmp_flag masknez和maskeqz顺序取反
   <  cmovb   cf = 1 zf = 0      sltu rd  A  B  | A < B
   <= cmovbe  cf = 1 or zf = 1   sltu rd  B  A  | B < A   使用cmp_flag
  ```

* CMP    A       B    signed     cmp-cmovcc

  ```c
  CMP   A       B   signed
  >   cmovg    ZF = 0 and SF = OF  slt rd  B  A  | B < A
  =   cmove    ZF = 1              sub rd  A  B  | A = B
  !=  cmovne   ZF = 0              sub rd  A  B  | A != B
  >=  cmovge   SF = OF             slt rd  A  B  | A < B   使用cmp_flag
  <   cmovl    SF != OF            slt rd  A  B  | A < B
  <=  cmovle   ZF = 1 or SF != OF  slt rd  B  A  | B < A   使用cmp_flag

      (A >= B)---> !(A < B)---->  !(slt A, B)
               //下面这两个还不确定，先不实现
                     cmovs    SF = 1
                     cmovns   SF = 0

  ```

* TEST   A             B        test-cmovcc

  ```c
             cmovs     SF = 1                  slt rd A  $zero | A < 0
             cmovns    SF = 0                  slt rd $zero A  | 0 < A
             cmove     ZF = 1                  and rd A  B     | rd = 0
             cmovne    ZF = 0                  and rd A  B     | rd != 0
             cmovle    ZF = 1 or SF != OF      slt rd $zero A  | 0 < A    使用cmp_flag
             cmovg     ZF = 0 and SF = OF = 0  slt rd $zero A  | 0 < A



         b cpu_tb_exec if itb->pc == 0x0000003ffffaeccb
  ```



##### pattern4: IR1层面的消除：cmpxchg-jcc 主要是cmpxchg-je,  cmpxchg-jne，主要是ZF的判断

```c
  IR1:
		 IR1[0] 0x554677:    cmpxchg     dword ptr [rbp], esi
  205015 IR1[1] 0x55467b:    je      0x554694

    //消除setx86j指令， 把X86sub.w变成 sub指令
  IR2:
  205017 [0, 0] -------   5588599
  205018 slli.w    ^[[31mitmp0^[[m,$s0,0
  205019 ld.w      ^[[32mitmp1^[[m,$s5,0
  205020 slli.w    ^[[33mitmp2^[[m,$s6,0
  205021 x86sub.w  ^[[31mitmp0^[[m,^[[32mitmp1^[[m   //直接相减sub, 如果相等 rd = 0, 如果不等 rd != 0
  205022 bne       ^[[32mitmp1^[[m,^[[31mitmp0^[[m,LABEL 1
  205023 st.w      ^[[33mitmp2^[[m,$s5,0
  205024 b         LABEL 2
  205025    -->    LABEL 1
  205026 bstrpick.d  $s0,^[[32mitmp1^[[m,31,0
  205027    -->    LABEL 2
  205028 [11, 1] -------   5588603
  205029 setx86j   ^[[31mitmp0^[[m,4
  205030 bne       ^[[31mitmp0^[[m,$zero,LABEL 3
  205031    -->    LABEL 4
  205032 b         0
  205033 and       $zero,$zero,$zero
  205034 lu12i.w   $fp,0xd0109
  205035 ori       $fp,$fp,0x700
  205036 lu32i.d   $fp,255
  205037 lu12i.w   $x,0x554
  205038 ori       $x,$x,0x67d
  205039 ori       ^[[36mitmp6^[[m,$fp,0x0
  205040    -->    LABEL 5
  205041 b         -271817
  205042 and       $zero,$zero,$zero
  205043    -->    LABEL 3
  205044    -->    LABEL 6
  205045 b         0

```

##### pattern 5: cmp-SETcc, test-SETcc 和 comisd-SETcc的优化
1. CMP--SETCC
```c
  unsigned
 >  seta   CF = 0 ZF = 0     sltu rd B  A | B < A 
 >= setae  CF = 0,ZF = 0/1   
 <  setb   CF = 1 ZF = 0     sltu rd A  B | A < B
 <= setbe  CF = 1 / ZF = 1

 =  sete   ZF = 1            
 =0 setz   ZF = 1        

 != setne  ZF = 0            
 !=0 setnz ZF = 0
 
  signed
  >  setg  ZF = 0 SF = OF   slt rd B  A | B < A
  >= setge SF = OF
  <  setl  SF != OF         slt rd A  B | A < B
  <= setle ZF = 1 | SF != OF


```

2. TEST--SETCC   没有做的价值
```c
  =  sete   ZF = 1    
  =0 setz   ZF = 1

  != setne  ZF = 0
  !=0 setnz ZF = 0
 
    setle  ZF = 1 or SF != OF      slt rd $zero A  | 0 < A    使用cmp_flag
    setg   ZF = 0 and SF = OF = 0  slt rd $zero A  | 0 < A

```

3. COMISD--SETCC
```c

```

# 优化方案
1. 现在的热路径识别代码只识别出热路径的头部， 整个trace的构建还需要使用构建CFG控制流图,控制流图CFG构建多大这是个问题？(约定一个深度)
hpath->trace中保存的是热路径的头TB, 根据每一个头TB构建CFG，然后在重新翻译的时候进行优化。自己使用struct node构建CFG
```
typedef struct node {

TranslationBlock* current_tb;

IR1_INST *ir1_inst_array;
int ir1_number;

IR2_INST *ir2_inst_array;
int ir2_number;

int real_ir2_inst_num

uintptr_t jmp_dest[2];

};
```
2. 函数内联
* 在重新翻译的时候，如果是call->return， 可以向后扫描一个TB，该TB的IR1是知道的，如果调用的函数是叶子函数，则把call和return 消除掉(用bitmap标记指令，标记的就消除掉)
* 可以做，但是有多少性能提升(主要是叶子节点函数太少)

3.

### 窥孔优化
1. cmp-jcc / test-jcc    Done


#### 现在实施方案的改进
1. 把enable_hot_profile放在env这个数据结构中，而不是TRANSLATE_BLOCK中，这样就可以采样一个TRACE，而不是一个TB,减少每个TB翻译时候的enable_hot_profile维护指令

2. 把TB的rb_count初始化为50,每次TB执行的时候tb_count--, 这样insert_collectpath_code中减少一条指令，少了加载阈值threshold的指令，tb_count直接与zero比较  “Done”

3. 由于上下文切换指令是公共的指令(store和load regs)，不需要每个TB的都进行插入，可以跳转到一个函数执行上下文的切换操作，减少指令膨胀,模仿generate_native_jmp_glue

4. 现在的无效TB需要断开TB link,效率很低，我们可以使新旧TB同时存在于code cache中，在旧TB的头部插入jmp指令，然后跳转到新的TB,这样就不用unlink了 "Done"

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
