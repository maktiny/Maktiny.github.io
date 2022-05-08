## 内核同步
1. 每CPU变量

2. 原子操作：Intel X86指令

* 指令(操作码)前缀lock（0xf0）该前缀指令是原子指令
* 指令前缀rep(0xf2, 0xf3)的汇编指令不是原子的。

```
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

```
# define barrier() __asm__ __volatile__("": : :"memory")
  ##编译器不能把asm中的指令与程序中的其他指令重新组合
```

2. 内存屏障
* 内存屏障的实现依赖于系统的体系结构，原子操作也起内存屏障的作用。

```
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
2. 
```
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

```
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

```
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
![参考]：https://zhuanlan.zhihu.com/p/67520807



### 信号量
 
```
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
* down()申请获得信号量:down()函数回阻塞，所以中断处理/延迟函数不调用down,
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

```
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
```
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
2. softirq机制
* 中断下半部 由 softirq（软中断） 机制来实现的
* softirq_vec 数组是 softirq 机制的核心，softirq_vec 数组每个元素代表一种软中断
* HI_SOFTIRQ 是高优先级tasklet，而 TASKLET_SOFTIRQ 是普通tasklet，tasklet是基于softirq机制的一种任务队列
* NET_TX_SOFTIRQ 和 NET_RX_SOFTIRQ 特定用于网络子模块的软中断
```c

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
