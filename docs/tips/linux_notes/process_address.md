# Process Address 

### 虚拟地址和物理地址的映射
![2022-05-07 10-26-19 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zmx3o35yj30u50kr0ud.jpg)
1. 虚拟内存：虚拟内存是使用软件虚拟的，在 32 位操作系统中，每个进程都独占 4GB 的虚拟内存空间。
2. 64位系统中使用48位虚拟内存空间(256TB大小)， 物理内存空间有40位，43(锐龙处理器)位的空间

## 进程线性地址空间
![2022-05-07 11-28-56 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zojxfvwgj30ic0kfgo2.jpg)
* 堆：用于存放使用 malloc 函数申请的内存,当申请的空间过大，超过了堆的大小，使用mmap分配mmap映射区
* mmap区：用于存放使用 mmap 函数映射的内存区。
* 栈：用于存放函数局部变量和函数参数
* 内核态访问用户态地址空间信息粗腰小心，可以加上__user注释，允许内核的一些处理函数检测使用是否合法。
```c
mm_alloc() 获得新的内存描述符 mm_struct
void mmput(struct mm_struct *mm)
{
	might_sleep();

	if (atomic_dec_and_test(&mm->mm_users))
		__mmput(mm);
}
EXPORT_SYMBOL_GPL(mmput);

do_mmap() # 分配线性地址区间 vm_area_struct

do_munmap() # 释放线性地址空间
   |
   ------split_vma()  #把释放的线性地址空间从大的线性地址空间中扣出来
   |
   ------unmap_region( ) #遍历线性区链表，并释放页框
```
### ELF文件
1. 一般一个 ELF 文件由以下三部分组成：
* ELF 头（ELF header）：描述应用程序的类型、CPU架构、入口地址、程序头表偏移和节头表偏移等等；
* 程序头表（Program header table）：列举了所有有效的段（segments）和他们的属性，程序头表需要加载器将文件中的段加载到虚拟内存段中；
* 节头表（Section header table）：包含对节（sections）的描述。
![2022-05-07 14-31-02 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1ztt9svywj30ex0m7q5r.jpg)

2. 所以，程序加载器可以通过 ELF 头中获取到程序头表的偏移量，然后通过程序头表的偏移量读取到程序头表的数据，再通过程序头表来获取到所有段的信息。
3. 加载ELF文件的主要使用load_elf_binary()实现
```c

0  load_elf_binary (bprm=0xffff88800561de00) at fs/binfmt_elf.c:824
#1  0xffffffff8132f148 in search_binary_handler (bprm=0xffff88800561de00)
    at fs/exec.c:1725
#2  exec_binprm (bprm=0xffff88800561de00) at fs/exec.c:1766
#3  bprm_execve (flags=<optimized out>, filename=<optimized out>, 
    fd=<optimized out>, bprm=0xffff88800561de00) at fs/exec.c:1835
#4  bprm_execve (bprm=0xffff88800561de00, fd=<optimized out>, 
    filename=<optimized out>, flags=<optimized out>) at fs/exec.c:1797
#5  0xffffffff8132f97d in do_execveat_common (fd=fd@entry=-100, 
    filename=0xffff888003eb2000, flags=0, argv=..., envp=...)
    at fs/exec.c:1924
#6  0xffffffff8132fc17 in do_execve (__envp=0x55dc1a8e1010, 
    __argv=0x7ffcfd5498e0, filename=<optimized out>) at fs/exec.c:1992
#7  __do_sys_execve (envp=0x55dc1a8e1010, argv=0x7ffcfd5498e0, 
    filename=<optimized out>) at fs/exec.c:2068
#8  __se_sys_execve (envp=<optimized out>, argv=<optimized out>, 
    filename=<optimized out>) at fs/exec.c:2063
#9  __x64_sys_execve (regs=<optimized out>) at fs/exec.c:2063
```


```c
 //linux内核中ELF文件程序头表的结构体
typedef struct elf64_phdr {
    Elf64_Word p_type;     // 段的类型
    Elf64_Word p_flags;    // 可读写标志
    Elf64_Off p_offset;    // 段在ELF文件中的偏移量
    Elf64_Addr p_vaddr;    // 段的虚拟内存地址
    Elf64_Addr p_paddr;    // 段的物理内存地址
    Elf64_Xword p_filesz;  // 段占用文件的大小
    Elf64_Xword p_memsz;   // 段占用内存的大小
    Elf64_Xword p_align;   // 内存对齐
} Elf64_Phdr;
```

## 缺页异常
```c
static __always_inline void
handle_page_fault(struct pt_regs *regs, unsigned long error_code,
			      unsigned long address)
{
	trace_page_fault_entries(regs, error_code, address);

	if (unlikely(kmmio_fault(regs, address)))
		return;

	/* Was the fault on kernel-controlled part of the address space? */
	if (unlikely(fault_in_kernel_space(address))) {
		do_kern_addr_fault(regs, error_code, address);
	} else {
		do_user_addr_fault(regs, error_code, address);
		/*
		 * User address page fault handling might have reenabled
		 * interrupts. Fixing up all potential exit points of
		 * do_user_addr_fault() and its leaf functions is just not
		 * doable w/o creating an unholy mess or turning the code
		 * upside down.
		 */
		local_irq_disable();
	}
}


handle_page_fault()  #处理缺页异常
       |
       |
 ---------------------------------------------
|                                             |
do_kern_addr_fault()                          do_user_addr_fault()   #处理用户态的缺页异常
    |
    ----spurious_kernel_fault()
    lazy TLB引起的异常,请求调页
 
    |
    ---kprobe_page_fault()

    |
    ---bad_area_nosemaphore()
    由内核bug,硬件故障引起的缺页异常


```

## 请求调页
```c
                                             handle_pte_fault()
                                                    |
                                                    |
                                                    |
     /*page不在内存,在交换区，换入*/       /*do_wp_page()写时复制*/
			do_swap_page(vmf);                      |
                                              -----wp_page_copy() 
                                              
 
```
## 创建进程的地址空间
```c
clone() ,fork(), vfork()的系统调用都是
调用系统函数——kernel_clone()
   fork()         vfork()     clone()
    |              |            |
    -----------------------------
    |
   kernel_clone()
        |
        ----copy_process() #创建(复制)子进程
        |       |
        |       -----dup_task_struct() #分配一个task_struct数据结构
        |       ---sched_fork()调度相关的初始化
        |       ---copy_mm()  #把父进程的地址空间复制给子进程
        |             |
        |            ---dup_mm()
        |                 |
        |                 ---dum_mmap() //复制父进程的页表到子进程
        |                      |
        |                      ----vm_area_dup()//为子进程创建一个VMA
        |                      ----__vm_link_rb()//把创建的VMA插入到子进程的mm中
        |                      ----copy_page_range()//复制父进程的页表项
        |
        |---------copy_thread()//函数复制父进程的struct pt_regs(段寄存器的值)栈框到子进程的栈框，
        |        在该函数设置childregs->ax = 0,fork()通过设置返回寄存器ax的这种方式，实现子进程返回0，父进程返回子进程PID。
        |----  wake_up_new_task()//唤醒进程，加入到调度队列

```
1. fork复制的开销就是：复制父进程的页表以及给子进程创建一个进程描述符,写时复制
2. vfork使用说明
* 由vfork创造出来的子进程还会导致父进程挂起，除非子进程exit或者execve才会唤起父进程
* 由vfok创建出来的子进程共享了父进程的所有内存，包括栈地址，直至子进程使用execve启动新的应用程序为止
* 由vfork创建出来得子进程不应该使用return返回调用者，或者使用exit()退出，但是它可以使用_exit()函数来退出
3. fork与vfork的区别
* fork会复制父进程的页表，而vfork不会复制，让子进程共享父进程的页表
* fork使用了写时复制技术，而vfork没有，即它任何时候都不会复制父进程地址空间
* fork父子进程执行次序不确定，一般先是子进程执行；vfork保证子进程现在执行。
* vfork()保证子进程先运行，在她调用exec或_exit之后父进程才可能被调度运行。如果在 调用这两个函数之前子进程依赖于父进程的进一步动作，则会导致死锁。

4. clone
* clone函数功能强大，带了众多参数，因此由他创建的进程要比前面2种方法要复杂，而fork与vfork都是无参数的，即共享那些资源早已规定。
* clone可以让你有选择性的继承父进程的资源，你可以选择想vfork一样和父进程共享一个虚存空间，从而使创造的是线程，你也可以不和父进程共享，你甚至可以选择创造出来的进程和父进程不再是父子关系，而是兄弟关系。

## 删除进程地址空间
      exit_mm()释放进程地址空间 



## heap 堆的管理
   sys_brk()系统调

## 

## 进程调度

## cpu负载均衡调度算法：调度域

```c
scheduler_tick()
    |
    -------trigger_load_balance  # 设置标志位，触发负载均衡

open_softirq()
  |
run_rebalance_doamins()
  |
rebalance_domains()    # 确定调用——load_balance()的频率
    |
    -------load_balance()
              |
              ---------detach_tasks()  #把需要迁移的进程从本地runqueue剥离
              |
              --------attach_tasks() # 注册到目的CPU的runqueue
              |
              ---------——sched_move_tasks() #修改迁移进程所属的cgroup,然后进行进程调度，使原来task_runing的进程在目的CPU运行起来

              #负载均衡完成

```

