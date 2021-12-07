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
<<<<<<< HEAD
    local_bh_enable() //打开可延迟函数，当preempt_count字段中的硬中断和软终端计数器
                      //都为0,并且有软中断挂起，调用do_softirq()打开软中断。


    local_bh_disable() //禁止可延迟函数
=======
    local_bh_enable() //打开软中断，当preempt_count字段中的硬中断和软终端计数器
                      //都为0,并且有软中断挂起，调用do_softirq()打开软中断。


    local_bh_disable()
>>>>>>> 974c71dd71c7c3f01a873bd001d8033f6c471b66

 ```



