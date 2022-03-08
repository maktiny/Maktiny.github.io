## TB exit

1. 每一个TB都是以跳转指令结尾的，在翻译跳转指令的时候会调用tr_generate_exit_tb()函数插入tb_exit代码，用来处理跳转。例如下面是一个TB最后的跳转指令 IR1[3] 0x402fd1:    jbe     0x402ff2 的翻译(直接跳转，在TB_link的情况下跳转地址已知,直接跳走)

   ```c
      /*下面两行是jbe的语义翻译*/
       1445 setx86j   ^[[31mitmp0^[[m,3
       1446 bne       ^[[31mitmp0^[[m,$zero,LABEL 2
       /*下面是tb_exit的插入代码，用来处理跳转。如果是(T_link)直接跳转，跳转地址已知，上面的代码直接跳走了，如果是unlink或者间接跳转的
       ，则上面的跳转地址类似nop，执行下面的代码。*/
       1447    -->    LABEL 4
       1448 b         0
       1449 lu12i.w   $fp,0xe8001
       1450 ori       $fp,$fp,0x780
       1451 lu32i.d   $fp,255
       1452 lu12i.w   $x,0x402
       1453 ori       $x,$x,0xfd3
       1454 ori       ^[[36mitmp6^[[m,$fp,0x0
       1455 b         -1568 // 跳转到
       1456    -->    LABEL 2
       /*跳转可能有两个出口，所以插入两个tb_exit*/
       1457    -->    LABEL 6
       1458 b         0
       1459 lu12i.w   $fp,0xe8001
       1460 ori       $fp,$fp,0x780
       1461 lu32i.d   $fp,255
       1462 lu12i.w   $x,0x402
       1463 ori       $x,$x,0xff2
       1464 ori       ^[[36mitmp6^[[m,$fp,0x1
       1465 b         -1576
   
   ```

### LATX 间接跳转处理

```c
    #0  generate_native_jmp_glue (code_buf=0xffef30c3d0, n=0)
    at ../target/i386/latx/translator/translate.c:2498
#1  0x000000aaaab57f88 in generate_native_rotate_fpu_by (code_buf_addr=0xffef30c1f8)
    at ../target/i386/latx/translator/translate.c:2869
#2  0x000000aaaabfd944 in target_latx_fpu_rotate (code_buf_addr=0xffef30c1f8)
    at ../target/i386/latx/latx-config.c:233
#3  0x000000aaaacd2e18 in tcg_target_qemu_prologue (s=0xaaab0b2738 <tcg_init_ctx>)
    at /home/loongson/lixu/lat/tcg/loongarch/tcg-target.c.inc:1800
#4  0x000000aaaacd4d80 in tcg_prologue_init (s=0xaaab0b2738 <tcg_init_ctx>)
    at ../tcg/tcg.c:1246
#5  0x000000aaaad04948 in main (argc=2, argv=0xffffff3a48, envp=0xffffff3a60)
    at ../linux-user/main.c:1072
        
        
        tcg_prologue_init()
          |
        tcg_target_qemu_prologue()
        |
        target_latx_fpu_rotate()
        |
        generate_native_rotate_fpu_by()
        |
        generate_native_jmp_glue()

```




1. 间接跳转是在generate_native_jmp_glue()处理的。在该函数中首先查找tb_jmp_cache[]数组，如果miss，则使用helper_lookup_tb()，该函数是一个宏，使用tb_lookup()函数注册。间接分支的查找也就是tb的查找，和tb的查找一样，使用快速的tb_jmp_cache[]数组查询，失败则使用tb_lookup()查找qht hash表查询。

   ```c
   /* code_buf: start code address
    * n = 0: direct fall through jmp
    * n = 1: direct taken jmp
    * n = 2: indirect jmps
    */
   
   /*
            * lookup HASH_JMP_CACHE
            * Step 1: calculate HASH = (x86_addr >> 12) ^ (x86_addr & 0xfff)
            * Step 2: load &HASH_JMP_CACHE[0]
            * Step 3: load tb = HASH_JMP_CACHE[HASH]
            * Step 4: if (tb == 0) {goto labal_miss}
            * Step 5: if (tb.pc == x86_addr) {goto fpu_rotate}
            *         else {goto labal_miss}
            */
      //target/i386/latx/translator/translate.c --2567  加载tb_jmp_cache的地址
   la_append_ir2_opnd2i(LISA_LD_D, addr_opnd, env_ir2_opnd,
                                lsenv_offset_of_tb_jmp_cache_ptr(lsenv));
                                  |----lsenv_offset_of_tb_jmp_cache_ptr()该函数返回tb_jmp_cache[]数组地址
           
       //target/i386/cpu.c --6252   
     #ifdef CONFIG_LATX
       env->tb_jmp_cache_ptr = s->tb_jmp_cache;
   #endif
   //CPUX86State的tb_jmp_cache_ptr指向CPUState的tb_jmp_cache，也就是全局的tb_jmp_cache
   
   ```

1. 如果上面的查找仍然失败，则进行上下文切换， generate_context_switch_native_to_bt()切换到QEMU的翻译进程进行翻译下一个TB

   > ```c
   > /*
   >          * if (next_tb != NULL) {goto fpu_rotate}
   >          * else {
   >          *   load eip to next_x86_addr
   >          *   clear v0
   >          *   jump to epilogue
   >          * }
   >  generate_context_switch_native_to_bt () at ../target/i386/latx/translator/translate.c:2441
   > #1  0x000000ff000ff400 in target_latx_epilogue (code_buf_addr=0xffe8000124)
   >     at ../target/i386/latx/latx-config.c:159
   > #2  0x000000ff002794cc in tcg_target_qemu_prologue (s=0xff00609980 <tcg_init_ctx>)
   >     at /home/loongson/lixu/lat2/tcg/loongarch/tcg-target.c.inc:1792
   > #3  0x000000ff0027b4c0 in tcg_prologue_init (s=0xff00609980 <tcg_init_ctx>) at ../tcg/tcg.c:1246
   > #4  0x000000ff002659f0 in main (argc=2, argv=0xffffff3458, envp=0xffffff3470)
   >     at ../linux-user/main.c:1085
   > ```
   
   
   
2.  call 函数调用的处理：这里对call next(call的跳转指令是下一条指令)和callthunk(i386计算pc)做了相应的优化----不用退出到翻译器。
   - 调整esp指针
   - 计算返回地址并压栈(使用JR_RA优化)
   - 如果使用影子栈，则把esp，return address等信息放到影子栈中
   - 使用QEMU函数tr_generate_exit_tb()生成退出tb,退出到BT(翻译器)
   
   
   
   
   
   ## TB link
   
   ```c
   /*当TB已经翻译好（已链接）的时候走这条路径*/
   #0  latx_tb_set_jmp_target (tb=0xffe80005c0 <code_gen_buffer+40>, n=0, 
       next_tb=0xffe8000900 <code_gen_buffer+872>) at ../target/i386/latx/translator/translate.c:3041
   #1  0x000000ff0026f54c in tb_add_jump (tb=0xffe80005c0 <code_gen_buffer+40>, n=0, 
       tb_next=0xffe8000900 <code_gen_buffer+872>) at ../accel/tcg/cpu-exec.c:480
   #2  0x000000ff0026fb7c in tb_find (cpu=0xfff7288010, last_tb=0xffe80005c0 <code_gen_buffer+40>, 
       tb_exit=0, cflags=0) at ../accel/tcg/cpu-exec.c:607
   #3  0x000000ff00270464 in cpu_exec (cpu=0xfff7288010) at ../accel/tcg/cpu-exec.c:958
   #4  0x000000ff000956e4 in cpu_loop (env=0xfff7308360) at ../linux-user/x86_64/../i386/cpu_loop.c:207
   #5  0x000000ff00265a74 in main (argc=2, argv=0xffffff3468, envp=0xffffff3480)
           
   /*当TB没有翻译（未链接）的时候走这条路径*/ jmp_reset_offset 是在未链接的情况下，直接跳转指令所指向的跳转目标。
   #0  tb_set_jmp_target (tb=0xffe80005c0 <code_gen_buffer+40>, n=0, addr=1099108976444)
       at ../accel/tcg/cpu-exec.c:409
   #1  0x000000ff002052ec in tb_reset_jump (tb=0xffe80005c0 <code_gen_buffer+40>, n=0)
       at ../accel/tcg/translate-all.c:1585
   #2  0x000000ff00205f50 in tb_gen_code (cpu=0xfff7288010, pc=4198656, cs_base=0, flags=4243635, 
       cflags=0) at ../accel/tcg/translate-all.c:2131
   #3  0x000000ff0026f978 in tb_find (cpu=0xfff7288010, last_tb=0x0, tb_exit=0, cflags=0)
       at ../accel/tcg/cpu-exec.c:554
   #4  0x000000ff00270464 in cpu_exec (cpu=0xfff7288010) at ../accel/tcg/cpu-exec.c:958
   #5  0x000000ff000956e4 in cpu_loop (env=0xfff7308360) at ../linux-user/x86_64/../i386/cpu_loop.c:207
   #6  0x000000ff00265a74 in main (argc=2, argv=0xffffff3468, envp=0xffffff3480)
       at ../linux-user/main.c:1098
   
   ```
   
   tb_find()函数中找到下一个TB (TB2), 如果上一个TB (TB1) (last_tb) 存在则调用tb_add_jump()使两个TB连接起来。
   
   ```c
   tb_find()
     |
     tb_add_jump()
        |
        latx_tb_set_jmp_target()
          |
          tb_set_jmp_target()
   ```
   
   
   
   ## 寄存器映射
   
   1. 通常的执行过程是在 TB 的最后一条指令通过 $t9 来存储接下来继续执行的 EIP，在上下文切换的时候会将 $t9 写入到 CPUX865State 中。回到 QEMU 后即可继续开始查找、翻译、执行下一个 TB。
      $v0 用作函数返回值，对于 helper 函数的调用返回，同样是通过 $v0 来获取其返回值。 
   
   ​    2. S_UD0 和 S_UD1 用于静态生成代码中的临时寄存器，详见【临时寄存器分配】
   
   ```c
    /* last exec tb */
       REG_MAP_DEF(S_UD0, la_fp),
       /* next x86 addr */
       REG_MAP_DEF(S_UD1, la_r21),
   ```
   
   
   
   ```c
    IR2_OPND la_ret_opnd = V0_RENAME_OPND;
    IR2_OPND tb_ptr_opnd = ra_alloc_dbt_arg1();
    IR2_OPND succ_x86_addr_opnd = ra_alloc_dbt_arg2();
       
   /*succ_x86_addr is set 1 for judging whether the instruction is direct jmp or condition jmp.*/
   ```
   
   3. a1 存放着 CPUX86State 的基地址，a0 存放着待执行 TB 的 native codes 所在的地
   
   4. zero_ir2_opnd 即寄存器号为 0 的 IR2_OPND_IREG 类型的 IR2_OPND ，即 LoongArch 的 zero 寄存器
   
   5. env_ir2_opnd 即 S2 寄存器，经过上下文切换后，S2 总是保存着 CPUX86State 的地址 通过各种偏移即可方便的访问其中的变量.
   
   6. sp_ir2_opnd 即 SP 寄存器，在上下文切换中用于申请栈空间保存上下文
   
   7. n1_ir2_opnd 即 S0 寄存器，经过上下文切换后，其值总是 0xFFFFFFFF ，即一个低 32 位为 1 的掩码
   
   8. eflags_ir2_opnd 即 S8 寄存器，用于映射 EFLAGS 的内容
   
   
   
   
   
   
