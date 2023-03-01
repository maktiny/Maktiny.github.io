#### 基础知识 
1. preeemptive kernel 运行在内核态的进程允许被抢占才叫抢占式内核

2. 每一个进程都有内核栈(4KB~12KB)，用来维护系统调用和临时量

3. (ASMP)非对称多处理器是一个处理器专用于内核，所有其他处理器运行用户态程序
    内核的吞吐量(系统调用)不随处理器数量的变化，都只有一个处理器处理内核操作

4. SMP对称多处理器为了保证只有一个处理器在临界区，必须实现同步(spin lock)

5. 设备树device tree.设备树的源码dts在/arch/arm/boot/dts文件夹中，dtc把dts源码
编译形成dtb,dtc是编译工具在/scripts/dtc路径下

6. 系统调用号存储在EAX，最多六个参数存储在EBX，ECX，EDX，ESI，EDI，EBP寄存器中
  通过INT 0x80中断方式进入系统调用(系统调用需要走中断处理流程),需要进行特权级的检查，
  通过sysenter指令方式直接进入系统调用sysenter 指令用于由 Ring3 进入 Ring0，SYSEXIT 
  指令用于由 Ring0 返回 Ring3。由于没有特权级别检查的处理，也没有压栈的操作，
  所以执行速度比 INT n/IRET 快了不少。sysenter和sysexit都是intel CPU原生支持的指令集
  后来又使用syscall 和sysret代替原来的系统调用，性能更快，不需要保存和恢复用户态栈指针

7. 有关[VDSO](https://zhuanlan.zhihu.com/p/436454953)的概述

8. 中断相关
![中断向量表中的entry](/home/liyi/programs/homepage/Maktiny.github.io/docs/pictures/x86/IDT_entry.png)
```c
中断向量
/*
 * Linux IRQ vector layout.
 *
 * There are 256 IDT entries (per CPU - each entry is 8 bytes) which can
 * be defined by Linux. They are used as a jump table by the CPU when a
 * given vector is triggered - by a CPU-external, CPU-internal or
 * software-triggered event.
 *
 * Linux sets the kernel code address each entry jumps to early during
 * bootup, and never changes them. This is the general layout of the
 * IDT entries:
 *
 *  Vectors   0 ...  31 : system traps and exceptions - hardcoded events
 *  Vectors  32 ... 127 : device interrupts
 *  Vector  128         : legacy int80 syscall interface
 *  Vectors 129 ... LOCAL_TIMER_VECTOR-1
 *  Vectors LOCAL_TIMER_VECTOR ... 255 : special interrupts
 *  64位每一个CPU有一个中断向量表
 * 64-bit x86 has per CPU IDT tables, 32-bit has one shared IDT table.
 *
 * This file enumerates the exact layout of them:
 */

```
9. 内核不允许softirq运行时间超过MAX_SOFTIRQ_TIME以及重新调度运行时间超过MAX_SOFTIRQ_RESTART
，超过之后所有pending的softirq都由ksoftirqd内核线程接手处理

10. 同步问题
```c

In process context: disable interrupts and acquire a spin lock; this will protect both against interrupt or other CPU cores race conditions (spin_lock_irqsave() and spin_lock_restore() combine the two operations)
In interrupt context: take a spin lock; this will will protect against race conditions with other interrupt handlers or process context running on different processors

We have the same issue for other interrupt context handlers such as softirqs, tasklets or timers and while disabling interrupts might work, it is recommended to use dedicated APIs:

In process context use spin_lock_bh() (which combines local_bh_disable() and spin_lock()) and spin_unlock_bh() (which combines spin_unlock() and local_bh_enable())
In bottom half context use: spin_lock() and spin_unlock() (or spin_lock_irqsave() and spin_lock_irqrestore() if sharing data with interrupt handlers)
```
11. RCU的使用案例
* RCU要支持新的数据结构很难，但是现有的API已经支持常见的lists, queues, trees数据结构
```c
/* list traversal */
rcu_read_lock();
list_for_each_entry_rcu(i, head) {
  /* no sleeping, blocking calls or context switch allowed */
}
rcu_read_unlock();


/* list element delete  */
spin_lock(&lock);
list_del_rcu(&node->list);
spin_unlock(&lock);
synchronize_rcu();
kfree(node);

/* list element add  */
spin_lock(&lock);
list_add_rcu(head, &node->list);
spin_unlock(&lock);
```

12. 内存管理debug
* SLAB/SLUB debugging-----内核支持的内存debug技术，需要在内核编译时打开编译选项Enable SLUB debugging support
* slub debug的实现原理很简单，就是在要分的memory周围放上围栏，正常的memory访问都只会集中在memory object里面，
不可能在外面，这样只要监视memory object周围的读写，就能发现不正常的memory访问，尤其是oob，也就是out of boundary，
越界访问，这个围栏就是red zone。此外，为了检查use after free，kernel把当前未被使用的object里的内容全部填成特殊值，
一旦发现有人在没有分配的情况下，写了object的值，就会报错，从而发现肇事者

```c
  //分配的object被填充一个初始值0x6b，使用之前检查不是则发生越界访问
               Redzone 0000000049e00626: cc cc cc cc cc cc cc cc                          ........
[  347.875744] Object 000000003760475c: 6b 6b 6b 6b 6b 6b 6b a5                          kkkkkkk.
[  347.884276] Redzone 0000000099655122: bb bb bb bb bb bb bb bb                          ........
```
* Kasan(内核检测工具，非常占用内存，需要用额外的内存来标记使用的内存) 是内核的一部分，使用时需要重新配置、编译并安装内核.
* Kmemleak内核中内存泄漏的检测工具

13. 内核中死锁检测
* CONFIG_DEBUG_LOCKDEP--- 锁循环依赖，不正确使用都可以检测

14. 内核补丁检测工具checkpatch.pl
