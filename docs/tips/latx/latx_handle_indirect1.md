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

   

2.  call 函数调用的处理：这里对call next(call的跳转指令是下一条指令)和callthunk(i386计算pc)做了相应的优化----不用退出到翻译器。
   - 调整esp指针
   - 计算返回地址并压栈(使用JR_RA优化)
   - 如果使用影子栈，则把esp，return address等信息放到影子栈中
   - 使用QEMU函数tr_generate_exit_tb()生成退出tb,退出到BT(翻译器)