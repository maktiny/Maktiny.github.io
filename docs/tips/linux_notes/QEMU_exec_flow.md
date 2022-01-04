### QEMU的执行流追踪

```
latx 使用qemu框架，但是摒弃了TCG, 直接使用ir1 -----> ir2的翻译。

                              cpu_loop()  for(;;){}
                              |
                              -----cpu_exec()
                                     |
                                     -----tb_find()
                                     |        |
                                     |        -----tb_gen_code()
                                     |               |
                                     |               ------target_latx_host()
                                     | 
                          cpu_loop_exec_tb()


/* target_latx_host() 
 * ---------------------------------------
 * |  tr_disasm()
 * |  -----------------------------------
 * |  |  ir1_disasm() <--get_ir1_list() -->该函数有个do-while循环反汇编整个TB
 * |  -----------------------------------
 * |  tr_translate_tb()
 * |  -----------------------------------
 * |  |  tr_init()
 * |  |  tr_ir2_generate()
 * |  |  --------------------------------
 * |  |  |  tr_init_for_each_ir1_in_tb()
 * |  |  |  ir1_translate(pir1) //call translate_xx function */
 * |  |  --------------------------------
 * |  |  tr_ir2_optimize()
 * |  |  tr_ir2_assemble()
 * |  |  tr_fini()
 * |  -----------------------------------
 * --------------------------------------- */
 
 qemu 中的 tb_gen_code()函数调用 target_latx_host(),
                         
```

### tb_find()追踪

1. tb_lookup() 从cache页中寻找tb
2. tb_gen_code():如果上一步没有找到tb,则翻译一个tb
3. 通过qatomic_set()原子操作，把上两部找到的tb的指针放到
tb_jmp_cache[]数组中。
4. tb_add_jump():把找到的tb或者翻译的tb链接起来。

#### tb_add_jump() 

1. latx_tb_set_jmp_target()把翻译好的tb链接起来

```
void latx_tb_set_jmp_target(TranslationBlock *tb, int n,
                                   TranslationBlock *next_tb)
{
    if (option_lsfpu || tb->_top_out == next_tb->_top_in) {
        tb_set_jmp_target(tb, n, (uintptr_t)next_tb->tc.ptr);
    } else {
        if (option_dump)
            fprintf(stderr,
                    "%p %p(" TARGET_FMT_lx ") %s to %p %p(" TARGET_FMT_lx ")\n",
                    tb, tb->tc.ptr, tb->pc,
                    n ? "jmp" : "fallthrough",
                    next_tb, next_tb->tc.ptr,
                    next_tb->pc);
        lsassert(next_tb != NULL);
        tb->next_tb[n] = next_tb; //把翻译好的tb链接起来，
        if (n == 0)
            tb_set_jmp_target(tb, 0, native_jmp_glue_0);
        else
            tb_set_jmp_target(tb, 1, native_jmp_glue_1);
    }
}
 
tb_set_jmp_target() 如果是直接跳转，则把tb块的跳转指令消除掉
 
```

#### tb_lookup()

1. tb_jmp_cache_hash_func()计算一级hash，从tb_jmp_cache[]
数组中找tb指针
2. tb_htable_lookup():没找到(hash冲突)就查找hash table
3. 如果找不到就返回0。

#### tb_htable_lookup()

1. tb_hash_func(),查找hash表，获取hash值
2. qht_lookup_custom(): 根据hash值，获取tb的指针

#### qht_lookup_custom()

1. seqlock_read_begin()：获取顺序锁，防止读写乱序
2. qht_do_lookup()：根据hash值，获取tb的指针
2. qht_lookup_slowpath():上两步获取顺序锁失败，调用慢路径
do/while获取顺序锁，然后使用qht_do_lookup()获取指向tb的指针。



### cpu_loop_exec_tb()的追踪

1. cpu_tb_exec() 循环执行翻译好的tb,
2. 每执行完一个tb,都要返回cpu_exec()函数处理中断和列外。

#### cpu_tb_exec()

1. tcg_qemu_tb_exec(CPUArchState , TranslationBlock) //负责执行tb
2. 如果last_tb不是退出tb，则将当前PC指向last_tb，顺着tb链往下执行。

```
 #ifdef CONFIG_LATX
    latx_before_exec_rotate_fpu(env, itb); //保存浮点上下文

    ret = tcg_qemu_tb_exec(env, tb_ptr);

    if (ret & ~TB_EXIT_MASK) {
        ret |= (uintptr_t)itb & 0xffffffff00000000LL;
    }
    latx_after_exec_rotate_fpu(env, itb);
#else
    ret = tcg_qemu_tb_exec(env, tb_ptr);
#endif
```
####  tcg_qemu_tb_exec()

1. qemu的执行tb函数

