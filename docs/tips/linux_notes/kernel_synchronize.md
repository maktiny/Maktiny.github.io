## 内核同步
1. 每CPU变量

2. 原子操作：Intel X86指令

* 指令(操作码)前缀lock（0xf0）该前缀指令是原子指令
* 指令前缀rep(0xf2, 0xf3)的汇编指令不是原子的。

```c
linux 中的原子操作
   atomic_read()
   atomic_set()
   atomic_add()
   atomic_t   #原子类型
··············

linux中原子位处理函数
   clear_bit()
   set_bit()
   ...............

```

3. 优化和内存屏障
4. 自旋锁
5. 信号量
6. 顺序锁
7. 本地中断禁止
8. 本地软中断禁止
9. RCU


### 优化和内存屏障

1. linux的优化屏障barrier()宏

```c
# define barrier() __asm__ __volatile__("": : :"memory")
  ##编译器保证barrier()之前的指令在之后的指令先执行
```

2. 内存屏障
* 内存屏障的实现依赖于系统的体系结构，原子操作也起内存屏障的作用。

```c
#ifdef CONFIG_X86_32
#define mb() asm volatile(ALTERNATIVE("lock; addl $0,-4(%%esp)", "mfence", \
				      X86_FEATURE_XMM2) ::: "memory", "cc")
#define rmb() asm volatile(ALTERNATIVE("lock; addl $0,-4(%%esp)", "lfence", \
				       X86_FEATURE_XMM2) ::: "memory", "cc")
#define wmb() asm volatile(ALTERNATIVE("lock; addl $0,-4(%%esp)", "sfence", \
				       X86_FEATURE_XMM2) ::: "memory", "cc")
#else
#define mb() 	asm volatile("mfence":::"memory")
#define rmb()	asm volatile("lfence":::"memory")
#define wmb()	asm volatile("sfence" ::: "memory")
#endif




#ifndef mb
#define mb()	barrier()
#endif

#ifndef rmb ###读内存屏障
#define rmb()	mb()
#endif

#ifndef wmb ##写内存屏障
#define wmb()	mb()
#endif

#ifndef dma_rmb
#define dma_rmb()	rmb()
#endif

#ifndef dma_wmb
#define dma_wmb()	wmb()
#endif

#ifndef __smp_mb  ###仅仅在SMP上有效
#define __smp_mb()	mb()
#endif

#ifndef __smp_rmb
#define __smp_rmb()	rmb()
#endif

#ifndef __smp_wmb
#define __smp_wmb()	wmb()
#endif


```

### 自旋锁

1. 在自旋锁忙等期间，内核抢占还是有效的，被更高优先级的进程抢占。

```c
/* Non PREEMPT_RT kernels map spinlock to raw_spinlock */
typedef struct spinlock {
	union {
		struct raw_spinlock rlock;

#ifdef CONFIG_DEBUG_LOCK_ALLOC
# define LOCK_PADSIZE (offsetof(struct raw_spinlock, dep_map))
		struct {
			u8 __padding[LOCK_PADSIZE];
			struct lockdep_map dep_map;
		};
#endif
	};
} spinlock_t;


typedef struct raw_spinlock {
	arch_spinlock_t raw_lock;
#ifdef CONFIG_DEBUG_SPINLOCK
	unsigned int magic, owner_cpu;
	void *owner;
#endif
#ifdef CONFIG_DEBUG_LOCK_ALLOC
	struct lockdep_map dep_map;
#endif
} raw_spinlock_t;


###  请求自旋锁
static __always_inline void spin_lock(spinlock_t *lock)
{
	raw_spin_lock(&lock->rlock);
}

static inline void __raw_spin_lock(raw_spinlock_t *lock)
{
	preempt_disable();
	spin_acquire(&lock->dep_map, 0, 0, _RET_IP_);
	LOCK_CONTENDED(lock, do_raw_spin_trylock, do_raw_spin_lock);
}

```

3. 读/写自旋锁 rwlock_t
* 读锁可以并发， 写锁必须独占，当锁被写者持有的时候，不可读。

```c
typedef struct {
	arch_rwlock_t raw_lock;
#ifdef CONFIG_DEBUG_SPINLOCK
	unsigned int magic, owner_cpu;
	void *owner;
#endif
#ifdef CONFIG_DEBUG_LOCK_ALLOC
	struct lockdep_map dep_map;
#endif
} rwlock_t;

#define read_trylock(lock)	__cond_lock(lock, _raw_read_trylock(lock))
#define write_trylock(lock)	__cond_lock(lock, _raw_write_trylock(lock))

#define write_lock(lock)	_raw_write_lock(lock)
#define read_lock(lock)		_raw_read_lock(lock)

```


### 顺序锁
1. 对某一个共享数据读取的时候不加锁，写的时候加锁。同时为了保证读取的
过程中因为写进程修改了共享区的数据，导致读进程读取数据错误。在读取者
和写入者之间引入了一个整形变量seqcount，读取者在读取之前读取seqcount, 
读取之后再次读取此值，如果不相同，则说明本次读取操作过程中数据发生了
更新，需要重新读取。而对于写进程在写入数据的时候就需要更新seqcount的值。     

2. 也就是说临界区只允许一个write进程进入到临界区，在没有write进程的话，
read进程来多少都可以进入到临界区。但是当临界区没有write进程的时候，
write进程就可以立刻执行，不需要等待。

```c
 //顺序锁
typedef struct {
	/*
	 * Make sure that readers don't starve writers on PREEMPT_RT: use
	 * seqcount_spinlock_t instead of seqcount_t. Check __SEQ_LOCK().
	 */
	seqcount_spinlock_t seqcount; #顺序计数器
	spinlock_t lock;
} seqlock_t;

```

### RCU
[参考]：(https://zhuanlan.zhihu.com/p/67520807)



### 信号量
 
```c
struct semaphore {
	raw_spinlock_t		lock;
	unsigned int		count;
	struct list_head	wait_list;
};

void up(struct semaphore *sem)
{
	unsigned long flags;

	raw_spin_lock_irqsave(&sem->lock, flags);
	if (likely(list_empty(&sem->wait_list)))
		sem->count++;
	else
		__up(sem);
	raw_spin_unlock_irqrestore(&sem->lock, flags);
}
EXPORT_SYMBOL(up);


/**
* up()函数释放信号量，如果等待队列为空，则信号量count++,
* 否则调用__up()唤醒等待队列的中的进程。
* 
* down()申请获得信号量:down()函数会阻塞，所以中断处理/延迟函数不调用down,
* 而是调用down_trylock()，该函数当count < 0时候，立即返回而不是挂起进程。
*
**/
extern void down(struct semaphore *sem);
extern int __must_check down_interruptible(struct semaphore *sem); //当count < 0时，该函数放弃申请信号量，而不是挂起。
extern int __must_check down_killable(struct semaphore *sem);
extern int __must_check down_trylock(struct semaphore *sem);
extern int __must_check down_timeout(struct semaphore *sem, long jiffies);
extern void up(struct semaphore *sem);

```

1. 读写信号量

```c
struct rw_semaphore {
	atomic_long_t count;
	/*
	 * Write owner or one of the read owners as well flags regarding
	 * the current state of the rwsem. Can be used as a speculative
	 * check to see if the write owner is running on the cpu.
	 */
	atomic_long_t owner;
#ifdef CONFIG_RWSEM_SPIN_ON_OWNER
	struct optimistic_spin_queue osq; /* spinner MCS lock */
#endif
	raw_spinlock_t wait_lock;
	struct list_head wait_list;
#ifdef CONFIG_DEBUG_RWSEMS
	void *magic;
#endif
#ifdef CONFIG_DEBUG_LOCK_ALLOC
	struct lockdep_map	dep_map;
#endif
};

//如果信号量关闭，则进程挂到等待队列的末尾，否则唤醒第一个进程，
//如果为写进程则其他进程继续睡眠，如果为读进程，则唤醒第一个写进程
//之前的所有读进程。 
```

2. 补充原语 completion
* 补充原语与信号量的的差别: 如何使用等待队列中的自旋锁
* * 使用自旋锁来确保 complete() 和wait_for_completio()并发执行。

* 为了防止在SMP上并发的访问信号量，使用补充原语：
假设进程A分配一个信号量，并调用down()，并传递给进程B, 之后A撤销分配，
摧毁信号量，B调用up()释放信号量，信号量已经不存在了。


```c
struct completion {
	unsigned int done;
	struct swait_queue_head wait;
};

struct swait_queue_head {
	raw_spinlock_t		lock;
	struct list_head	task_list;
};

补充原语中
 up() ---------------- complete()
 down() -------------- wait_for_completion()
```

### 信号
1. 在task_struct结构体中与信号相关的元素

```c
struct task_struct {
  .....................................
	struct signal_struct		*signal;
	struct sighand_struct __rcu		*sighand;
	sigset_t			blocked;
	sigset_t			real_blocked;
	/* Restored if set_restore_sigmask() was used: */
	sigset_t			saved_sigmask;
	struct sigpending		pending;
...............................
}

struct signal_struct {
	refcount_t		sigcnt;
	atomic_t		live;
	int			nr_threads;
	struct list_head	thread_head;

	wait_queue_head_t	wait_chldexit;	/* for wait4() */

	/* current thread group signal load-balancing target: */
	struct task_struct	*curr_target;

	/* shared signal handling: */
	struct sigpending	shared_pending;

	/* For collecting multiprocess signals during fork */
	struct hlist_head	multiprocess;

........................
}

struct sigpending {
	struct list_head list;//存储着进程接收到的信号队列,当进程接收到一个信号时，就需要把接收到的信号添加 pending 这个队列中
	sigset_t signal;
};

struct sighand_struct {
	spinlock_t		siglock;
	refcount_t		count;
	wait_queue_head_t	signalfd_wqh;
	struct k_sigaction	action[_NSIG];//数组中的每个成员代表着相应信号的处理函数的信息
};

struct k_sigaction {
	struct sigaction sa;
#ifdef __ARCH_HAS_KA_RESTORER
	__sigrestore_t ka_restorer;
#endif
};

struct sigaction {
#ifndef __ARCH_HAS_IRIX_SIGACTION
	__sighandler_t	sa_handler;//其中 sa_handler 成员是类型为 __sighandler_t 的函数指针，代表着信号处理的方法。
	unsigned long	sa_flags;
#else
	unsigned int	sa_flags;
	__sighandler_t	sa_handler;
#endif
#ifdef __ARCH_HAS_SA_RESTORER
	__sigrestore_t sa_restorer;
#endif
	sigset_t	sa_mask;	/* mask last for extensibility */
};

```
2. 可以通过 kill() 系统调用发送一个信号给指定的进程，其原型如下：
```c
int kill (__pid_t __pid, int __sig) 

///kill()系统调用使用内核函数sys_kill()
SYSCALL_DEFINE2(kill, pid_t, pid, int, sig)
{
	struct kernel_siginfo info;

	prepare_kill_siginfo(sig, &info);//初始化kernel_siginfo结构体

	return kill_something_info(sig, &info, pid);
}

kill_something_info() 函数根据传入pid 的不同来进行不同的操作，有如下4中可能：

pid 等于0时，表示信号将送往所有与调用 kill() 的那个进程属同一个使用组的进程。
pid 大于零时，pid 是信号要送往的进程ID。
pid 等于-1时，信号将送往调用进程有权给其发送信号的所有进程，除了进程1(init)。
pid 小于-1时，信号将送往以-pid为组标识的进程


kill_something_info() 最后会调用send_signal()-->__send_signal()把信号放到信号队列里去。
```

3. 内核触发信号处理函数是在arch_do_signal_or_restart()--->handle_signal()

```c

void arch_do_signal_or_restart(struct pt_regs *regs, bool has_signal)
{
	struct ksignal ksig;

	if (has_signal && get_signal(&ksig)) {
		/* Whee! Actually deliver the signal.  */
		handle_signal(&ksig, regs);
		return;
	}
  ..................................
}
```
4. 信号处理程序是由用户提供的，所以信号处理程序的代码是在用户态的
先返回到用户态执行信号处理程序，执行完信号处理程序后再返回到内核态，再在内核态完成收尾工作
![2022-05-10 14-27-47 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h23aoyun8ej30so0cxtbj.jpg)
handle_signal()--->setup_rt_frame()--->ia32_setup_frame()函数来构建这个过程的(从用户态返回到内核态)运行环境（其实就是修改内核栈和用户栈相应的数据来完成）

```c

int ia32_setup_frame(int sig, struct ksignal *ksig,
		     compat_sigset_t *set, struct pt_regs *regs)
{
	struct sigframe_ia32 __user *frame;
	void __user *restorer;
	void __user *fp = NULL;

	/* copy_to_user optimizes that into a single 8 byte store */
	static const struct {
		u16 poplmovl;
		u32 val;
		u16 int80;
	} __attribute__((packed)) code = {//调用系统调用sigreturn()返回内核态
		0xb858,		 /* popl %eax ; movl $...,%eax */
		__NR_ia32_sigreturn,
		0x80cd,		/* int $0x80 */
	};

	frame = get_sigframe(ksig, regs, sizeof(*frame), &fp);

	if (ksig->ka.sa.sa_flags & SA_RESTORER) {
		restorer = ksig->ka.sa.sa_restorer;
	} else {
		/* Return stub is in 32bit vsyscall page */
		if (current->mm->context.vdso)
			restorer = current->mm->context.vdso +
				vdso_image_32.sym___kernel_sigreturn;
		else
			restorer = &frame->retcode;
	}

	if (!user_access_begin(frame, sizeof(*frame)))
		return -EFAULT;

	unsafe_put_user(sig, &frame->sig, Efault);
	unsafe_put_sigcontext32(&frame->sc, fp, regs, set, Efault);
	unsafe_put_user(set->sig[1], &frame->extramask[0], Efault);
	unsafe_put_user(ptr_to_compat(restorer), &frame->pretcode, Efault);
	/*
	 * These are actually not used anymore, but left because some
	 * gdb versions depend on them as a marker.
	 */
	unsafe_put_user(*((u64 *)&code), (u64 __user *)frame->retcode, Efault);
	user_access_end();

	/* Set up registers for signal handler */
	regs->sp = (unsigned long) frame;
	regs->ip = (unsigned long) ksig->ka.sa.sa_handler;//调用注册好的信号处理函数

	/* Make -mregparm=3 work */
	regs->ax = sig;
	regs->dx = 0;
	regs->cx = 0;

	loadsegment(ds, __USER32_DS);
	loadsegment(es, __USER32_DS);

	regs->cs = __USER32_CS;
	regs->ss = __USER32_DS;

	return 0;
Efault:
	user_access_end();
	return -EFAULT;
}

```
6.sigreturn() 要做的工作就是恢复原来内核栈的内容了 
```c

COMPAT_SYSCALL_DEFINE0(sigreturn)
{
	struct pt_regs *regs = current_pt_regs();
	struct sigframe_ia32 __user *frame = (struct sigframe_ia32 __user *)(regs->sp-8);
	sigset_t set;

	if (!access_ok(frame, sizeof(*frame)))
		goto badframe;
	if (__get_user(set.sig[0], &frame->sc.oldmask)
	    || __get_user(((__u32 *)&set)[1], &frame->extramask[0]))
		goto badframe;

	set_current_blocked(&set);

	if (ia32_restore_sigcontext(regs, &frame->sc))///最重要的是调用 ia32_restore_sigcontext() 恢复原来内核栈的内容
		goto badframe;
	return regs->ax;

badframe:
	signal_fault(regs, frame, "32bit sigreturn");
	return 0;
}

```
7. 注册信号处理函数是在sys_signal()系统调用中处理

```c


SYSCALL_DEFINE2(signal, int, sig, __sighandler_t, handler)
{
	struct k_sigaction new_sa, old_sa;
	int ret;

	new_sa.sa.sa_handler = handler;//注册信号处理函数
	new_sa.sa.sa_flags = SA_ONESHOT | SA_NOMASK;
	sigemptyset(&new_sa.sa.sa_mask);

	ret = do_sigaction(sig, &new_sa, &old_sa);//相关数据结构的初始

	return ret ? ret : (unsigned long)old_sa.sa.sa_handler;
}
```




### 中断
1. 中断上下文中，用户态进入内核态的时候，只需要保存部分寄存器的值，包含在pt_regs结构体中
2. 可以使用request_irq（）和free_irq（）函数来动态的注册和删除中断
3. 中断处理的三步： 从用户态切换到内核态-->执行中断上半部(中断处理程序)--->切换到用户态-->执行软中断(中断的下半部)

```c 


struct pt_regs {
/*
 * C ABI says these regs are callee-preserved. They aren't saved on kernel entry
 * unless syscall needs a complete, fully filled "struct pt_regs".
 */
	unsigned long r15;
	unsigned long r14;
	unsigned long r13;
	unsigned long r12;
	unsigned long bp;
	unsigned long bx;
/* These regs are callee-clobbered. Always saved on kernel entry. */
	unsigned long r11;
	unsigned long r10;
	unsigned long r9;
	unsigned long r8;
	unsigned long ax;
	unsigned long cx;
	unsigned long dx;
	unsigned long si;
	unsigned long di;
/*
 * On syscall entry, this is syscall#. On CPU exception, this is error code.
 * On hw interrupt, it's IRQ number:
 */
	unsigned long orig_ax;
/* Return frame for iretq */
	unsigned long ip;
	unsigned long cs;
	unsigned long flags;
	unsigned long sp;
	unsigned long ss;
/* top of stack page */
};

```
### 禁止本地中断
1. 禁止本地中断并不保护运行在另一个CPU核上的中断
处理程序对数据结构的并发访问。所以禁止本地中断与
自旋锁结合使用。

```
#define local_irq_enable()	do { raw_local_irq_enable(); } while (0)  //使用sti指令设置eflag寄存器实现
#define local_irq_disable()	do { raw_local_irq_disable(); } while (0) // cli
#define local_irq_save(flags)	do { raw_local_irq_save(flags); } while (0) // pushf 压栈指令
#define local_irq_restore(flags) do { raw_local_irq_restore(flags); } while (0) // popf
#define safe_halt()		do { raw_safe_halt(); } while (0)

```


### 禁止和激活可延迟函数（软中断和tasklet）
 
 ```
    local_bh_enable() //打开可延迟函数，当preempt_count字段中的硬中断和软终端计数器
                      //都为0,并且有软中断挂起，调用do_softirq()打开软中断。


    local_bh_disable() //禁止可延迟函数
 ```
 
### 中断 IRQ
1. 在内核中每条IRQ线使用irq_desc描述
 ```c

struct irq_desc {
	struct irq_common_data	irq_common_data;
	struct irq_data		irq_data;
	unsigned int __percpu	*kstat_irqs;
	irq_flow_handler_t	handle_irq;
	struct irqaction	*action;	/* IRQ action list */
  //action:中断信号的处理入口。由于一条IRQ线可以被多个硬件共享，所以 action 是一个链表，每个 action 代表一个硬件的中断处理入口。
	unsigned int		status_use_accessors;
	unsigned int		core_internal_state__do_not_mess_with_it;
	unsigned int		depth;		/* nested irq disables */
	unsigned int		wake_depth;	/* nested wake enables */
	unsigned int		tot_count;
	unsigned int		irq_count;	/* For detecting broken IRQs */
	unsigned long		last_unhandled;	/* Aging timer for unhandled count */
	unsigned int		irqs_unhandled;
	atomic_t		threads_handled;
	int			threads_handled_last;
	raw_spinlock_t		lock;
	struct cpumask		*percpu_enabled;
	const struct cpumask	*percpu_affinity;
#ifdef CONFIG_SMP
	const struct cpumask	*affinity_hint;
	struct irq_affinity_notify *affinity_notify;
#ifdef CONFIG_GENERIC_PENDING_IRQ
	cpumask_var_t		pending_mask;
#endif
#endif
	unsigned long		threads_oneshot;
	atomic_t		threads_active;
	wait_queue_head_t       wait_for_threads;
#ifdef CONFIG_PM_SLEEP
	unsigned int		nr_actions;
	unsigned int		no_suspend_depth;
	unsigned int		cond_suspend_depth;
	unsigned int		force_resume_depth;
#endif
#ifdef CONFIG_PROC_FS
	struct proc_dir_entry	*dir;
#endif
#ifdef CONFIG_GENERIC_IRQ_DEBUGFS
	struct dentry		*debugfs_file;
	const char		*dev_name;
#endif
#ifdef CONFIG_SPARSE_IRQ
	struct rcu_head		rcu;
	struct kobject		kobj;
#endif
	struct mutex		request_mutex;
	int			parent_irq;
	struct module		*owner;
	const char		*name;
} ____cacheline_internodealigned_in_smp;



struct irqaction {
	irq_handler_t		handler;//中断处理的入口函数，handler 的第一个参数是中断号，第二个参数是设备对应的ID，第三个参数是中断发生时由内核保存的各个寄存器的值
	                                //对于共享中断线的情况，可以通过dev_id来表示该中断来源是哪一个设备。
	void			*dev_id;
	void __percpu		*percpu_dev_id;
	struct irqaction	*next;
	irq_handler_t		thread_fn;
	struct task_struct	*thread;
	struct irqaction	*secondary;
	unsigned int		irq;
	unsigned int		flags;
	unsigned long		thread_flags;
	unsigned long		thread_mask;
	const char		*name;
	struct proc_dir_entry	*dir;
} ____cacheline_internodealigned_in_smp;


struct irq_data {
	u32			mask;
	unsigned int		irq;
	unsigned long		hwirq;
	struct irq_common_data	*common;
	struct irq_chip		*chip;
	struct irq_domain	*domain;
#ifdef	CONFIG_IRQ_DOMAIN_HIERARCHY
	struct irq_data		*parent_data;
#endif
	void			*chip_data;
};

//struct irq_chip - hardware interrupt chip descriptor
//IRQ控制器，该结构体描述了体系结构的无关的IRQ控制器，函数指针提供的函数改变IRQ的状态。
struct irq_chip {
	struct device	*parent_device;
	const char	*name;
	unsigned int	(*irq_startup)(struct irq_data *data);
	void		(*irq_shutdown)(struct irq_data *data);
	void		(*irq_enable)(struct irq_data *data);
	void		(*irq_disable)(struct irq_data *data);

	void		(*irq_ack)(struct irq_data *data);
	void		(*irq_mask)(struct irq_data *data);
	void		(*irq_mask_ack)(struct irq_data *data);
	void		(*irq_unmask)(struct irq_data *data);
	void		(*irq_eoi)(struct irq_data *data);

	int		(*irq_set_affinity)(struct irq_data *data, const struct cpumask *dest, bool force);
	int		(*irq_retrigger)(struct irq_data *data);
	int		(*irq_set_type)(struct irq_data *data, unsigned int flow_type);
	int		(*irq_set_wake)(struct irq_data *data, unsigned int on);

	void		(*irq_bus_lock)(struct irq_data *data);
	void		(*irq_bus_sync_unlock)(struct irq_data *data);

	void		(*irq_cpu_online)(struct irq_data *data);
	void		(*irq_cpu_offline)(struct irq_data *data);

	void		(*irq_suspend)(struct irq_data *data);
	void		(*irq_resume)(struct irq_data *data);
	void		(*irq_pm_shutdown)(struct irq_data *data);

	void		(*irq_calc_mask)(struct irq_data *data);

	void		(*irq_print_chip)(struct irq_data *data, struct seq_file *p);
	int		(*irq_request_resources)(struct irq_data *data);
	void		(*irq_release_resources)(struct irq_data *data);

	void		(*irq_compose_msi_msg)(struct irq_data *data, struct msi_msg *msg);
	void		(*irq_write_msi_msg)(struct irq_data *data, struct msi_msg *msg);

	int		(*irq_get_irqchip_state)(struct irq_data *data, enum irqchip_irq_state which, bool *state);
	int		(*irq_set_irqchip_state)(struct irq_data *data, enum irqchip_irq_state which, bool state);

	int		(*irq_set_vcpu_affinity)(struct irq_data *data, void *vcpu_info);

	void		(*ipi_send_single)(struct irq_data *data, unsigned int cpu);
	void		(*ipi_send_mask)(struct irq_data *data, const struct cpumask *dest);

	int		(*irq_nmi_setup)(struct irq_data *data);
	void		(*irq_nmi_teardown)(struct irq_data *data);

	unsigned long	flags;
};

```

2. 在内核中，可以通过__setup_irq() 函数来注册一个中断处理入口


```c
int setup_percpu_irq(unsigned int irq, struct irqaction *act)
{
	struct irq_desc *desc = irq_to_desc(irq);//通过中断号获取irq_desc结构体
	int retval;

	if (!desc || !irq_settings_is_per_cpu_devid(desc))
		return -EINVAL;

	retval = irq_chip_pm_get(&desc->irq_data);
	if (retval < 0)
		return retval;

	retval = __setup_irq(irq, desc, act);

	if (retval)
		irq_chip_pm_put(&desc->irq_data);

	return retval;
}

```
3. 当一个中断发生时，中断控制层会发送信号给CPU，CPU收到信号会中断当前的执行，转而执行中断处理过程。中断处理过程首先会保存寄存器的值到栈中

```c
handle_irq_event()--->handle_irq_event_percpu()--->__handle_irq_event_percpu()----->然后调用中断注册时候action的处理函数进行中断处理
```

### softirq 机制
1. 由于中断处理一般在关闭中断的情况下执行，所以中断处理不能太耗时，否则后续发生
的中断就不能实时地被处理。鉴于这个原因，Linux把中断处理分为两个部分，上半部 和
下半部.一般中断 上半部 只会做一些最基础的操作（比如从网卡中复制数据到缓存中），
然后对要执行的中断 下半部 进行标识，标识完调用 do_softirq() 函数进行处理。
中断下半部也叫做可延迟操作.
2. softirq机制
* 中断下半部 由 softirq（软中断） 机制来实现的
* softirq_vec 数组是 softirq 机制的核心，softirq_vec 数组每个元素代表一种软中断
* HI_SOFTIRQ 是高优先级tasklet，而 TASKLET_SOFTIRQ 是普通tasklet，tasklet是基于softirq机制的一种任务队列
* NET_TX_SOFTIRQ 和 NET_RX_SOFTIRQ 特定用于网络子模块的软中断
```c
//默认情况下，
static struct softirq_action softirq_vec[NR_SOFTIRQS] __cacheline_aligned_in_smp;


struct softirq_action
{
	void	(*action)(struct softirq_action *);
};

enum
{
	HI_SOFTIRQ=0,
	TIMER_SOFTIRQ,
	NET_TX_SOFTIRQ,
	NET_RX_SOFTIRQ,
	BLOCK_SOFTIRQ,
	IRQ_POLL_SOFTIRQ,
	TASKLET_SOFTIRQ,
	SCHED_SOFTIRQ,
	HRTIMER_SOFTIRQ,
	RCU_SOFTIRQ,    /* Preferable RCU should always be the last softirq */

	NR_SOFTIRQS
};

```
3. 通过open_softirq()注册softirq处理函数
* open_softirq() 函数的主要工作就是向 softirq_vec 数组添加一个softirq处理函数。
```c

void open_softirq(int nr, void (*action)(struct softirq_action *))
{
	softirq_vec[nr].action = action;
}
Linux在系统初始化时注册了两种softirq处理函数，分别为 TASKLET_SOFTIRQ 和 HI_SOFTIRQ
void __init softirq_init(void)
{
	int cpu;

	for_each_possible_cpu(cpu) {
		per_cpu(tasklet_vec, cpu).tail =
			&per_cpu(tasklet_vec, cpu).head;
		per_cpu(tasklet_hi_vec, cpu).tail =
			&per_cpu(tasklet_hi_vec, cpu).head;
	}

	open_softirq(TASKLET_SOFTIRQ, tasklet_action);
	open_softirq(HI_SOFTIRQ, tasklet_hi_action);
}

```
4. 处理softirq
```c

asmlinkage __visible void do_softirq(void)
{
	__u32 pending;
	unsigned long flags;

	if (in_interrupt())
		return;

	local_irq_save(flags);

	pending = local_softirq_pending();

	if (pending && !ksoftirqd_running(pending))
		do_softirq_own_stack();//宏展开最后调用__do_softirq()函数

	local_irq_restore(flags);
}

```
### tasklet机制
1. tasklet机制是基于softirq机制的，tasklet机制其实就是一个任务队列，
然后通过softirq执行。在Linux内核中有两种tasklet，一种是高优先级tasklet，一种是普通tasklet。这两种tasklet的实现基本一致，唯一不同的就是执行的优先级，高优先级tasklet会先于普通tasklet执行。

```c

struct tasklet_head {
	struct tasklet_struct *head;
	struct tasklet_struct **tail;
};


struct tasklet_struct
{
	struct tasklet_struct *next;
	unsigned long state;
	atomic_t count;
	bool use_callback;
	union {
		void (*func)(unsigned long data);
		void (*callback)(struct tasklet_struct *t);
	};
	unsigned long data;
};

```
2. tasklet本质是一个队列，通过结构体 tasklet_head 存储，并且每个CPU有一个这样的队列 
3. 	__tasklet_schedule_common()--->raise_softirq_irqoff()--->__raise_softirq_irqoff()设置相应的标志位，打开softirq,
然后softirq_init初始化的时候注册tasklet_action函数会被执行

```c
//两个tasklet队列
static DEFINE_PER_CPU(struct tasklet_head, tasklet_vec);
static DEFINE_PER_CPU(struct tasklet_head, tasklet_hi_vec);

//注册tasklet到系统中
static inline void tasklet_schedule(struct tasklet_struct *t)
{
	if (!test_and_set_bit(TASKLET_STATE_SCHED, &t->state))
		__tasklet_schedule(t);
}

extern void __tasklet_hi_schedule(struct tasklet_struct *t);

static inline void tasklet_hi_schedule(struct tasklet_struct *t)
{
	if (!test_and_set_bit(TASKLET_STATE_SCHED, &t->state))
		__tasklet_hi_schedule(t);
}


//两个taskle队列的调度
void __tasklet_schedule(struct tasklet_struct *t)
{
	__tasklet_schedule_common(t, &tasklet_vec,
				  TASKLET_SOFTIRQ);
}
EXPORT_SYMBOL(__tasklet_schedule);

void __tasklet_hi_schedule(struct tasklet_struct *t)
{
	__tasklet_schedule_common(t, &tasklet_hi_vec,
				  HI_SOFTIRQ);
}
EXPORT_SYMBOL(__tasklet_hi_schedule);




void __init softirq_init(void)
{
	int cpu;

	for_each_possible_cpu(cpu) {
		per_cpu(tasklet_vec, cpu).tail =
			&per_cpu(tasklet_vec, cpu).head;
		per_cpu(tasklet_hi_vec, cpu).tail =
			&per_cpu(tasklet_hi_vec, cpu).head;
	}
    ///softirq_init初始化的时候注册tasklet_action函数会被执行
	open_softirq(TASKLET_SOFTIRQ, tasklet_action);
	open_softirq(HI_SOFTIRQ, tasklet_hi_action);
}



static __latent_entropy void tasklet_action(struct softirq_action *a)
{
	tasklet_action_common(a, this_cpu_ptr(&tasklet_vec), TASKLET_SOFTIRQ);
}

static __latent_entropy void tasklet_hi_action(struct softirq_action *a)
{
	tasklet_action_common(a, this_cpu_ptr(&tasklet_hi_vec), HI_SOFTIRQ);
}
```
4. tasklet_action_common()函数就是遍历tasklet_hi_vec或者tasklet_vec队列，执行其中的处理函数


#### 等待队列
1. __add_wait_queue() 将一个进程加入到等待队列，__add_wait_queue_exclusive()进程加入到等待队列的尾部，

```c


struct wait_queue_entry {
	unsigned int		flags;
	void			*private;//指向等待的进程task_struct
	wait_queue_func_t	func;//唤醒进程的函数
	struct list_head	entry;
};

typedef struct wait_queue_entry wait_queue_entry_t;

struct wait_queue_head {
	spinlock_t		lock;
	struct list_head	head;//双链表，用来实现队列
};
typedef struct wait_queue_head wait_queue_head_t;


//初始化等待队列
#define DEFINE_WAIT_FUNC(name, function)					\
	struct wait_queue_entry name = {					\
		.private	= current,					\
		.func		= function,					\
		.entry		= LIST_HEAD_INIT((name).entry),			\
	}

#define DEFINE_WAIT(name) DEFINE_WAIT_FUNC(name, autoremove_wake_function)

//初始化等待队列的实体
static inline void init_waitqueue_entry(struct wait_queue_entry *wq_entry, struct task_struct *p)
{
	wq_entry->flags		= 0;
	wq_entry->private	= p;
	wq_entry->func		= default_wake_function;
}


//当创建等待队列之后，宏wait_event无线循环，直到条件满足，把进程状态置为TASK_RUNNING，然后从等待队列中移除
#define wait_event(wq_head, condition)						\
do {										\
	might_sleep();								\
	if (condition)								\
		break;								\
	__wait_event(wq_head, condition);					\
} while (0)




//唤醒进程
#define wake_up(x)			__wake_up(x, TASK_NORMAL, 1, NULL)
#define wake_up_nr(x, nr)		__wake_up(x, TASK_NORMAL, nr, NULL)
#define wake_up_all(x)			__wake_up(x, TASK_NORMAL, 0, NULL)
#define wake_up_locked(x)		__wake_up_locked((x), TASK_NORMAL, 1)
#define wake_up_all_locked(x)		__wake_up_locked((x), TASK_NORMAL, 0)

```

































