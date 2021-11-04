# Process Address 

## 进程调度

## cpu负载均衡调度算法：调度域

```
scheduler_tick()
    |
    -------trigger_load_balance  # 设置标志位，触发负载均衡

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

## 线性地址空间
```
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
## 缺页异常
```
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
```
                                             handle_pte_fault()
                                                    |
                                                    |
                                                    |
     /*page不在内存,在交换区，换入*/       /*do_wp_page()写时复制*/
			do_swap_page(vmf);                      |
                                              -----wp_page_copy() 
                                              
 
``` 
## 创建进程的地址空间
```
clone() ,fork(), vfork()的系统调用都是
调用系统函数——kernel_clone()

   kernel_clone()
        |
        ----copy_process() #创建(复制)子进程
               |
               ---copy_mm()  #把父进程的地址空间复制给子进程
                     |
                     ---dup_mm()
                         |
                         ---dum_mmap() 

```

## 删除进程地址空间
      exit_mm()释放进程地址空间 



## heap 堆的管理
   sys_brk()系统调


## 