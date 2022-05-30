### 进程

1. 0号(idle)进程是在init_task.c中静态初始化的，start_kernel()函数完成
内核数据结构初始化之后，调用arch_call_rest_init()--->rest_init()---->调用内核kernel_init()
,1号(init)进程创建，之后进程0回执行cpu_idle()（当就绪队里中没有可执行进程), 在SMP中，每个CPU都有
一个0号进程。

2. fork(),vfork(),clone()系统调用都是使用内核线程kernel_clone()实现的，
fork()只复制父进程的页表项，实现写时复制。vfork()的父进程一直会阻塞，直到
子进程退出为止，由于父进程回挂起，所以vfork()父子进程运行在相同的进程地址空间
，所以vfork()不用复制父进程的页表项。clone()可以通过flag控制从父进程继承的资源。

3. 内核进程与内核线程都是用task_struct数据结构描述，内核线程没有独立的进程地址空间，
task_struct的mm指向为NULL

4. kthread_create()函数创建的内核线程必须使用wake_up_process()放到就绪队列中，
kthread_run()创建的内核线程马上就可以运行。

5. 进程终止途径：
* 从main函数退出，链接程序回自动添加exit()
* 自动调用exit()
* 收到一个SIGKILL终止信号，或者不能处理的信号
* 进程在内核态执行产生异常。
* 若先于父进程终结，子进程僵死，直到父进程调用wait()才终结
* 若后于父进程死亡，init进程将变成该进程的新的父进程。


```c
clone() ,fork(), vfork()的系统调用都是
调用系统函数——kernel_clone()
   fork()         vfork()     clone()
    |              |            |
    -----------------------------
    |
   kernel_clone()
        |
        |----copy_process() #创建(复制)子进程
        |       |
        |       -----dup_task_struct() #分配一个task_struct数据结构
        |       ---sched_fork()调度相关的初始化
        |              |---------------- __sched_fork(clone_flags, p);//初始化一个空的调度实体sched_entity
        |              |-----p->sched_class = &fair_sched_class;
        |              //通过宏调用方法集中的task_fork_fair()继续初始化
        |                                   |--------update_curr()更新父进程的vruntime
        |                                   |-------palce_entity()对进程的虚拟时间进行惩罚
        |                                             |---vruntime = sched_vslice(cfs_rq, se)//计算虚拟时间
        |                                  ###子进程的vruntime选取两者中的最打值 se->vruntime = max_vruntime(se->vruntime, vruntime);
        |
        |---------copy_mm()  #把父进程的地址空间复制给子进程 
        |             |
        |            ---dup_mm()
        |                 |
        |                 ---dum_mmap() //复制父进程的页表项到子进程
        |                      |
        |                      ----vm_area_dup()//为子进程创建一个VMA
        |                      ----__vm_link_rb()//把创建的VMA插入到子进程的mm中
        |                      ----copy_page_range()//复制父进程的页表项
        |
        |---------copy_thread()//函数复制父进程的struct pt_regs(段寄存器的值)栈框到子进程的栈框，
        |        在该函数设置childregs->ax = 0,fork()通过设置返回寄存器ax的这种方式，实现子进程返回0，父进程返回子进程PID。
        |
        |------wake_up_new_task()//唤醒进程，加入到调度队列
                 |--__set_task_cpu(p, select_task_rq(p, task_cpu(p), WF_FORK));//选取最空暇的CPU
                 |--activate_task(rq, p, ENQUEUE_NOCLOCK);
                        |                
                //调用enqueue_task()把进程加入到调度器(就绪队列)中,enqueue_task调度类方法注册的方法为enqueue_task_fair()
                 #enqueue_task_fair()
                            |---update_load_avg(cfs_rq, se, UPDATE_TG | DO_ATTACH);//跟新进程和整个CFS就绪队列的负载
                            |----__enqueue_entity()将实体插入到调度就绪队列
```

#### 进程调度原语

1. nice值默认0，-20 ~ 19,nice值越大，优先级越低,nice()函数可以修改nice值
2. 内核使用0 ~ 139表示进程的优先级，数值越小，优先级越大。
3. 0 ~ 99分给实时进程，100 ~ 139封普通进程-->nice值映射到普通进程的优先级.


```c
struct task_struct{

        int				prio; //动态优先级
	int				static_prio; //静态优先级
	int				normal_prio; //根据static_prio和调度策略计算出来的优先级
	unsigned int			rt_priority;//实时优先级
	
}



//调度器调度的对象是sched_entity，进程组或者进程(task_struct中包含sched_entity元素)都可以是调度实体
struct sched_entity {
	/* For load-balancing: */
	struct load_weight		load;
	struct rb_node			run_node;
	struct list_head		group_node;
	unsigned int			on_rq;

	u64				exec_start;
	u64				sum_exec_runtime;
	u64				vruntime;
	u64				prev_sum_exec_runtime;

	u64				nr_migrations;

	struct sched_statistics		statistics;

#ifdef CONFIG_FAIR_GROUP_SCHED
	int				depth;
	struct sched_entity		*parent;
	/* rq on which this entity is (to be) queued: */
	struct cfs_rq			*cfs_rq;
	/* rq "owned" by this entity/group: */
	struct cfs_rq			*my_q;
	/* cached value of my_q->h_nr_running */
	unsigned long			runnable_weight;
#endif

#ifdef CONFIG_SMP
	/*
	 * Per entity load average tracking.
	 *
	 * Put into separate cache line so it does not
	 * collide with read-mostly values above.
	 */
	struct sched_avg		avg;
#endif
};
//就绪队列
struct rq {
	/* runqueue lock: */
	raw_spinlock_t		__lock;

	/*
	 * nr_running and cpu_load should be in the same cacheline because
	 * remote CPUs use both these fields when doing load calculation.
	 */
	unsigned int		nr_running;
...............................................
	struct cfs_rq		cfs;
	struct rt_rq		rt;   //各个就绪队列中插入的特定调度器类的子就绪队列
	struct dl_rq		dl;

#ifdef CONFIG_FAIR_GROUP_SCHED
	/* list of leaf cfs_rq on this CPU: */
	struct list_head	leaf_cfs_rq_list;
	struct list_head	*tmp_alone_branch;
#endif /* CONFIG_FAIR_GROUP_SCHED */

	/*
	 * This is part of a global counter where only the total sum
	 * over all CPUs matters. A task can increase this counter on
	 * one CPU and if it got migrated afterwards it may decrease
	 * it on another CPU. Always updated under the runqueue lock:
	 */
	unsigned int		nr_uninterruptible;

	struct task_struct __rcu	*curr;
	struct task_struct	*idle;
	struct task_struct	*stop;
	unsigned long		next_balance;
	struct mm_struct	*prev_mm;

	unsigned int		clock_update_flags;
	u64			clock;
	/* Ensure that all clocks are in the same cache line */
	u64			clock_task ____cacheline_aligned;
	u64			clock_pelt;
	unsigned long		lost_idle_time;

	atomic_t		nr_iowait;
.........................................................
#ifdef CONFIG_SCHED_CORE
	/* per rq */
	struct rq		*core;
	struct task_struct	*core_pick;
	unsigned int		core_enabled;
	unsigned int		core_sched_seq;
	struct rb_root		core_tree;

	/* shared state -- careful with sched_core_cpu_deactivate() */
	unsigned int		core_task_seq;
	unsigned int		core_pick_seq;
	unsigned long		core_cookie;
	unsigned char		core_forceidle;
	unsigned int		core_forceidle_seq;
#endif
};


//系统定义了一个全局变量就绪队列rq runqueues[] 数组，数组中每个元素对应每个cpu
DEFINE_PER_CPU_SHARED_ALIGNED(struct rq, runqueues);

```


#### 调度策略

1. linux把调度策略抽象成调度类：stop, deadline, realtime, CFS, idle
2. 实时进程 > 完全公平进程 > 空闲进行
3. 调度类在内核编译时候确认，没有运行时添加的机制

| 调度类   | 调度策略                              | 使用范围                       | 说明                                                         |
| -------- | ------------------------------------- | ------------------------------ | ------------------------------------------------------------ |
| stop     | 无                                    | 最高优先级的进程               | 负载均衡中的进程迁移，热插拔，可抢占任何进程                 |
| deadline | SHCED_DEADLINE                        | 最高优先级的实时进程，优先级-1 | 用于由实时性要求的进程，视频编解码                           |
| realtime | SCHED_FIFO,SCHED_RR                   | 普通进程，优先级0 ~ 99         | 普通进程，IRQ进程等                                          |
| CFS      | SCHED_NORMAL, SCHED_BATCH, SCHED_IDLE | 优先级100 ~ 139                | 由CFS来调度                                                  |
| idle     | 无                                    | 最低优先级的进程               | 当就绪队列中没有进程的时候进入idle调度类，使CPU进入低功耗模式 |

```c
#define SCHED_NORMAL		0
#define SCHED_FIFO		1   #先进先出调度策略
#define SCHED_RR		2   #循环调度策略
#define SCHED_BATCH		3   #批处理调度，使用CFS调度策略
/* SCHED_ISO: reserved but not implemented yet */
#define SCHED_IDLE		5 
#define SCHED_DEADLINE		6
//内核判断调度策略的函数
static inline int idle_policy(int policy)
{
	return policy == SCHED_IDLE;
}
static inline int fair_policy(int policy)
{
	return policy == SCHED_NORMAL || policy == SCHED_BATCH;
}

static inline int rt_policy(int policy)
{
	return policy == SCHED_FIFO || policy == SCHED_RR;
}

static inline int dl_policy(int policy)
{
	return policy == SCHED_DEADLINE;
}

```
2. 调度类的操作方法集(sched_class封装了调度类的相关方法)

```c
struct sched_class {

#ifdef CONFIG_UCLAMP_TASK
	int uclamp_enabled;
#endif

	void (*enqueue_task) (struct rq *rq, struct task_struct *p, int flags);
	void (*dequeue_task) (struct rq *rq, struct task_struct *p, int flags);
	void (*yield_task)   (struct rq *rq);
	bool (*yield_to_task)(struct rq *rq, struct task_struct *p);

  -----------------------------
}
```

#### 完全公平调度CFS

1. vruntime虚拟运行时间
2. 优先级越高，vruntime越小，CFS选取红黑树中当前CPU的就绪队列中最小vruntime的进程作为调度进程。

```c
//完全公平调度CFS的就绪队列
/* CFS-related fields in a runqueue */
struct cfs_rq {
	struct load_weight	load;
	unsigned int		nr_running;
	unsigned int		h_nr_running;      /* SCHED_{NORMAL,BATCH,IDLE} */
	unsigned int		idle_h_nr_running; /* SCHED_IDLE */

	u64			exec_clock;
	u64			min_vruntime;
#ifdef CONFIG_SCHED_CORE
	unsigned int		forceidle_seq;
	u64			min_vruntime_fi;
#endif

#ifndef CONFIG_64BIT
	u64			min_vruntime_copy;
#endif

	struct rb_root_cached	tasks_timeline;

	/*
	 * 'curr' points to currently running entity on this cfs_rq.
	 * It is set to NULL otherwise (i.e when none are currently running).
	 */
	struct sched_entity	*curr;
	struct sched_entity	*next;
	struct sched_entity	*last;
	struct sched_entity	*skip;
...................................
}
///权重
struct load_weight {
	unsigned long			weight;
	u32				inv_weight;
};

//调度实体
struct sched_entity {
	/* For load-balancing: */
	struct load_weight		load;
	struct rb_node			run_node;
	struct list_head		group_node;
	unsigned int			on_rq;

	u64				exec_start;
	u64				sum_exec_runtime;
	u64				vruntime;
	u64				prev_sum_exec_runtime;

	u64				nr_migrations;

	struct sched_statistics		statistics;

-----------------------------------
};

// nice 值对应的权重表
const int sched_prio_to_weight[40] = {
 /* -20 */     88761,     71755,     56483,     46273,     36291,
 /* -15 */     29154,     23254,     18705,     14949,     11916,
 /* -10 */      9548,      7620,      6100,      4904,      3906,
 /*  -5 */      3121,      2501,      1991,      1586,      1277,
 /*   0 */      1024,       820,       655,       526,       423,
 /*   5 */       335,       272,       215,       172,       137,
 /*  10 */       110,        87,        70,        56,        45,
 /*  15 */        36,        29,        23,        18,        15,
};

/*
 * Inverse (2^32/x) values of the sched_prio_to_weight[] array, precalculated.
 *
 * In cases where the weight does not change often, we can use the
 * precalculated inverse to speed up arithmetics by turning divisions
 * into multiplications:
 */

//load_weight中元素inv_weigth对应的值的表
const u32 sched_prio_to_wmult[40] = {
 /* -20 */     48388,     59856,     76040,     92818,    118348,
 /* -15 */    147320,    184698,    229616,    287308,    360437,
 /* -10 */    449829,    563644,    704093,    875809,   1099582,
 /*  -5 */   1376151,   1717300,   2157191,   2708050,   3363326,
 /*   0 */   4194304,   5237765,   6557202,   8165337,  10153587,
 /*   5 */  12820798,  15790321,  19976592,  24970740,  31350126,
 /*  10 */  39045157,  49367440,  61356676,  76695844,  95443717,
 /*  15 */ 119304647, 148102320, 186737708, 238609294, 286331153,
};
            delta_exec(实际运行时间) * nice_0_weigth(nice值为0的权重)
vruntime = ------------------------------------------
                  进程的实际权重
```

#### 实时调度rt
1. 有两种实时调度进程：SCHED_RR 循环调度进程   SCHED_FIFO 先入先出进程(组织和调度方式不同)
```c

//实时调度的就绪队列
struct rt_rq {
	struct rt_prio_array	active;
	unsigned int		rt_nr_running;
	unsigned int		rr_nr_running;
#if defined CONFIG_SMP || defined CONFIG_RT_GROUP_SCHED
	struct {
		int		curr; /* highest queued rt task prio */
#ifdef CONFIG_SMP
		int		next; /* next highest */
#endif
	} highest_prio;
#endif
#ifdef CONFIG_SMP
	unsigned int		rt_nr_migratory;
	unsigned int		rt_nr_total;
	int			overloaded;
	struct plist_head	pushable_tasks;

#endif /* CONFIG_SMP */
	int			rt_queued;

	int			rt_throttled;
	u64			rt_time;
	u64			rt_runtime;
	/* Nests inside the rq lock: */
	raw_spinlock_t		rt_runtime_lock;

#ifdef CONFIG_RT_GROUP_SCHED
	unsigned int		rt_nr_boosted;

	struct rq		*rq;
	struct task_group	*tg;
#endif
};

```

#### 进程调度

* 调度时机
1. 在阻塞操作中(信号量，等待队列)
2. 中断返回，系统调用返回
3. 唤醒的进程进行调度检查

```c
asmlinkage __visible void __sched schedule(void)
{
	struct task_struct *tsk = current;

	sched_submit_work(tsk);
	do {
		preempt_disable();
		__schedule(SM_NONE);
		sched_preempt_enable_no_resched(); //preemt_enable()函数会检查是否需要调度
	} while (need_resched());
	sched_update_worker(tsk);
}
EXPORT_SYMBOL(schedule);

 
	/*
	 * kernel -> kernel   lazy + transfer active   | 内核线程使用内核地址空间，不能访问用户态地址空间，所以不需要刷新TLB,
	 *   user -> kernel   lazy + mmgrab() active   | 这就是lazy_tlb模式，减少tlb的刷新。
	 *
	 * kernel ->   user   switch + mmdrop() active
	 *   user ->   user   switch
	 */
	
schedule() //可中断的函数
    |
__schedule()
  |------schedule_debug(prev, !!sched_mode); //判断当前进程是否处于atomic上下文
  |
  |-----pick_next_task(rq, prev, &rf);//选取下一个调度的进程
  |      |---__pick_next_task()
  |               |--pick_next_task_fair()//如果当前进程的调度类是CFS,并且所有就绪队列的数量与CFS进程数相同(就绪队列里都是CFS调度类),使用该函数
  |               |        // 否则遍历所有调度类(从高优先级stop开始),使用相应调度类注册的pick_next_task()选取下一个调度进程
  |           
  |-----context_switch(rq, prev, next, &rf);//进行上下文切换
         |
         |---	prepare_task_switch() -->prepare_task() //设置next进程的on_cpu为1，表示当前进程即将进入执行状态
         |---	membarrier_switch_mm()//加内存屏障，确保切换之前
         |
         |
         |全局TLB：虚实地址映射关系不会改变,进程切换不需要刷新TLB
         |进程独有的TLB:进程切换需要刷新TLB,进程地址空间ID(ASID)标识TLB属于某个进程
         |switch_mm_irqs_off()通过ASID的比较，确定是否需要刷新TLB
         |
  TLB处理|--switch_mm_irqs_off()等同于switch_mm()--其调用switch_mm_irqs_off().
         |  //把新进程的页表基址放到CR3页表基址寄存器中
         |    |
页表基址 |    |--load_new_mm_cr3()
         |    |--switch_ldt() //切换局部描述符表
         |                           |----| 
         |---switch_to(prev, next, prev); | //进程切换的核心函,进程切换之后第一个prev指向next,所以需要第二个prev指向切换前的进程
栈空间   |    |--- __switch_to_asm((prev),| (next));	//汇编写的函数，做栈的切换(栈指针)，然后跳转到__switch_to()
         |            |---__switch_to()   | //做一些cpu上下文的切换(TLS,fpu,段寄存器等)
         |                                |
         |                                |
         |                         --------
         | //进程A--->进程B        |
         |---finish_task_switch(prev)//该函数由切换之后的进程B执行
            //该函数与prepare_task_switch()成对存在，做一些清理工作。
  

```

#### 周期性调度  scheduler_tick()

```c
#0  scheduler_tick () at kernel/sched/core.c:5196
#1  0xffffffff81142d3b in update_process_times (user_tick=0) at kernel/time/timer.c:1790
#2  0xffffffff8115317b in tick_periodic (cpu=cpu@entry=0) at ./arch/x86/include/asm/ptrace.h:136
#3  0xffffffff811531f5 in tick_handle_periodic (dev=0xffffffff830dd980 <i8253_clockevent>) at kernel/time/tick-common.c:112
#4  0xffffffff8103ac98 in timer_interrupt (irq=<optimized out>, dev_id=<optimized out>) at arch/x86/kernel/time.c:57
#5  0xffffffff8111db32 in __handle_irq_event_percpu (desc=desc@entry=0xffff888003dc8c00, flags=flags@entry=0xffffc90000003f54) at kernel/irq/handle.c:156
#6  0xffffffff8111dc83 in handle_irq_event_percpu (desc=desc@entry=0xffff888003dc8c00) at kernel/irq/handle.c:196
#7  0xffffffff8111dd0b in handle_irq_event (desc=desc@entry=0xffff888003dc8c00) at kernel/irq/handle.c:213
#8  0xffffffff8112207e in handle_level_irq (desc=0xffff888003dc8c00) at kernel/irq/chip.c:653
#9  0xffffffff810395e3 in generic_handle_irq_desc (desc=0xffff888003dc8c00) at ./include/linux/irqdesc.h:158
#10 handle_irq (regs=<optimized out>, desc=0xffff888003dc8c00) at arch/x86/kernel/irq.c:231
#11 __common_interrupt (regs=<optimized out>, vector=48) at arch/x86/kernel/irq.c:250
#12 0xffffffff81c03035 in common_interrupt (regs=0xffffffff82e03e08, error_code=<optimized out>) at arch/x86/kernel/irq.c:240
#13 0xffffffff81e00cde in asm_common_interrupt () at ./arch/x86/include/asm/idtentry.h:629
#14 0xffffffff82e1a110 in envp_init ()



             scheduler_tick() //周期调度
              |-- update_rq_clock() //更新当前cpu就绪队列的时钟计数
              |
              |--task_tick()//使用相应调度类注册的如：task_tick_fair()
              |      |
              |      task_tick_fair()//遍历每个调度实体shced_entity
              |           |
              |        entity_tick()//将该进程的vruntime与就绪队列红黑树中最左边的进程的vruntime比较，看是否需要出发调度
              |            |--update_curr(cfs_rq);//更新当前就绪队列的vruntime
              |            |
              |            |--update_load_avg()//更新负载
              |            |
              |            |--check_preempt_tick()//检查当前进程是否需要调度delta_exec > idle_runtime，需要调度
              |               //通过resched_curr()设置thread_info为TIF_NEED_RESCHED
              |
              |
              |--trigger_load_balance(rq);//触发负载均衡
                       |
		raise_softirq()//触发软中断，中断处理函数在时候的时候调用run_rebalance_domains()---->rebalance_domains()




```

#### 组调度机制

1. CFS的调度粒度是进程，组调度的粒度是用户组task_group
2. 组调度属于cgroup架构中cpu的子系统。


```c
struct task_group {
	struct cgroup_subsys_state css;

#ifdef CONFIG_FAIR_GROUP_SCHED
	/* schedulable entities of this group on each CPU */
	struct sched_entity	**se;
	/* runqueue "owned" by this group on each CPU */
	struct cfs_rq		**cfs_rq;
	unsigned long		shares;

	/* A positive value indicates that this is a SCHED_IDLE group. */
	int			idle;
----------------------------------

#endif

#ifdef CONFIG_RT_GROUP_SCHED
	struct sched_rt_entity	**rt_se;
	struct rt_rq		**rt_rq;

	struct rt_bandwidth	rt_bandwidth;
#endif

	struct rcu_head		rcu;
	struct list_head	list;

	struct task_group	*parent;
	struct list_head	siblings;
	struct list_head	children;

	struct cfs_bandwidth	cfs_bandwidth;
----------------------------------------------
#ifdef CONFIG_UCLAMP_TASK_GROUP
	/* The two decimal precision [%] value requested from user-space */
	unsigned int		uclamp_pct[UCLAMP_CNT];
	/* Clamp values requested for a task group */
	struct uclamp_se	uclamp_req[UCLAMP_CNT];
	/* Effective clamp values used for a task group */
	struct uclamp_se	uclamp[UCLAMP_CNT];
#endif

};

            shced_create_group()//创建一个组调度
             |
             |--alloc_rt_sched_group()//创建实时调度所需的组调度结构
             |
             |--alloc_fair_sched_group()//创建CFS所需的组调度结构
                |----init_cfs_rq() //初始化就绪队列
                |---init_tg_cfs_entry()//初始化组调度相关参数。

```

#### SMP负载均衡

1. 内核对CPU的管理通过位图bitmap
2. 在SMP系统上通过调度实现负载均衡(把进程从繁忙的CPU就绪队列迁移到空闲的就绪队列中)
```c
 // 表示可运行的cpu核数
#define cpu_possible_mask ((const struct cpumask *)&__cpu_possible_mask)
//表示正在运行的cpu核数
#define cpu_online_mask   ((const struct cpumask *)&__cpu_online_mask)
//表示可处于运行态的核数(有些核被热插拔)
#define cpu_present_mask  ((const struct cpumask *)&__cpu_present_mask)
//表示活跃的核数
#define cpu_active_mask   ((const struct cpumask *)&__cpu_active_mask)
#define cpu_dying_mask    ((const struct cpumask *)&__cpu_dying_mask)


start_kernel --> arch_call_rest_init()-->rest_init()--->kernel_init()---> 
-->kernel_init_freeable()--->smp_init()-->smp_cpus_done()//激活cpu并设置cpu_active_mask中;


```

##### CPU的调度域
1. 调度组是负载均衡的最小单位，在最底层的调度域中通常一个调度组描述一个CPU

```c
start_kernel --> arch_call_rest_init()-->rest_init()--->kernel_init()---> 
-->kernel_init_freeable()--->sched_init_smp()-->sched_init_domains()--build_sched_domains()-->主要的构造调度域的函数

    build_sched_domains()
       |---__visit_domain_allocation_hell()--__sdt_alloc()分配shced_domain,sched_group等数据结构
       |---build_sched_domain()构建调度域
       |--build_sched_group()构建调度组
//调度组
struct sched_group {
	struct sched_group	*next;			/* Must be a circular list */
	atomic_t		ref;

	unsigned int		group_weight;
	struct sched_group_capacity *sgc;
	int			asym_prefer_cpu;	/* CPU of highest priority in group */

	/*
	 * The CPUs this group covers.
	 *
	 * NOTE: this field is variable length. (Allocated dynamically
	 * by attaching extra space to the end of the structure,
	 * depending on how many CPUs the kernel has booted up with)
	 */
	unsigned long		cpumask[];
};

 //调度域描述符(一个CPU核是一个调度域)
struct sched_domain {
	/* These fields must be setup */
	struct sched_domain __rcu *parent;	/* top domain must be null terminated */
	struct sched_domain __rcu *child;	/* bottom domain must be null terminated */
	struct sched_group *groups;	/* the balancing groups of the domain */
	unsigned long min_interval;	/* Minimum balance interval ms */
	unsigned long max_interval;	/* Maximum balance interval ms */
	unsigned int busy_factor;	/* less balancing by factor if busy */
	unsigned int imbalance_pct;	/* No balance until over watermark */
	unsigned int cache_nice_tries;	/* Leave cache hot tasks for # tries */

	int nohz_idle;			/* NOHZ IDLE status */
	int flags;			/* See SD_* */
	int level;

	/* Runtime fields. */
	unsigned long last_balance;	/* init to jiffies. units in jiffies */
	unsigned int balance_interval;	/* initialise to 1. units in ms. */
	unsigned int nr_balance_failed; /* initialise to 0 */

	/* idle_balance() stats */
	u64 max_newidle_lb_cost;
	unsigned long next_decay_max_lb_cost;

	u64 avg_scan_cost;		/* select_idle_sibling */

#ifdef CONFIG_SCHEDSTATS
	/* load_balance() stats */
	unsigned int lb_count[CPU_MAX_IDLE_TYPES];
	unsigned int lb_failed[CPU_MAX_IDLE_TYPES];
	unsigned int lb_balanced[CPU_MAX_IDLE_TYPES];
	unsigned int lb_imbalance[CPU_MAX_IDLE_TYPES];
	unsigned int lb_gained[CPU_MAX_IDLE_TYPES];
	unsigned int lb_hot_gained[CPU_MAX_IDLE_TYPES];
	unsigned int lb_nobusyg[CPU_MAX_IDLE_TYPES];
	unsigned int lb_nobusyq[CPU_MAX_IDLE_TYPES];

	/* Active load balancing */
	unsigned int alb_count;
	unsigned int alb_failed;
	unsigned int alb_pushed;

	/* SD_BALANCE_EXEC stats */
	unsigned int sbe_count;
	unsigned int sbe_balanced;
	unsigned int sbe_pushed;

	/* SD_BALANCE_FORK stats */
	unsigned int sbf_count;
	unsigned int sbf_balanced;
	unsigned int sbf_pushed;

	/* try_to_wake_up() stats */
	unsigned int ttwu_wake_remote;
	unsigned int ttwu_move_affine;
	unsigned int ttwu_move_balance;
#endif
#ifdef CONFIG_SCHED_DEBUG
	char *name;
#endif
	union {
		void *private;		/* used during construction */
		struct rcu_head rcu;	/* used during destruction */
	};
	struct sched_domain_shared *shared;

	unsigned int span_weight;
	/*
	 * Span of all CPUs in this domain.
	 *
	 * NOTE: this field is variable length. (Allocated dynamically
	 * by attaching extra space to the end of the structure,
	 * depending on how many CPUs the kernel has booted up with)
	 */
	unsigned long span[];
};


```

2. 
```c
//用来描述CPU的层次关系的描述符
struct sched_domain_topology_level {
	sched_domain_mask_f mask; //cpu位图掩码
	sched_domain_flags_f sd_flags;
	int		    flags;
	int		    numa_level;
	struct sd_data      data;
#ifdef CONFIG_SCHED_DEBUG
	char                *name;
#endif
};

//用一个数组来概括CPU的物理域的层次结构,每个CPU都有一套SDTL调度域
static struct sched_domain_topology_level default_topology[] = {
#ifdef CONFIG_SCHED_SMT //超线程SMT，其使用相同的CPU资源，共享L1级缓存
	{ cpu_smt_mask, cpu_smt_flags, SD_INIT_NAME(SMT) },
#endif
#ifdef CONFIG_SCHED_MC //多核MC， 每个物理核心共享L1级缓存
	{ cpu_coregroup_mask, cpu_core_flags, SD_INIT_NAME(MC) },
#endif
	{ cpu_cpu_mask, SD_INIT_NAME(DIE) }, //处理器级别
	{ NULL, },
};

cpu_smt_mask() //SMT层级的cpu位图的组成方式
cpu_coregroup_mask()//MC
cpu_cpu_mask() //DIE
    
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
              |---should_we_balance()//是否需要进行负载均衡
              |
              |--find_busiest_group()//查找调度域中最繁忙的调度组
              |
              |
              |---find_busiest_queue()//查找刚刚找到的调度组中最繁忙的就绪队列
              ---------detach_tasks()  #把需要迁移的进程从本地runqueue剥离
              |
              --------attach_tasks() # 注册到目的CPU的runqueue
              |
              ---------——sched_move_tasks() #修改迁移进程所属的cgroup,然后进行进程调度，使原来task_runing的进程在目的CPU运行起来

              #负载均衡完成
```

