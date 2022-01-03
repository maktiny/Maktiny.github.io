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

```


#### 调度策略

1. linux把调度策略抽象成调度类：stop, deadline, realtime, CFS, idle


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

```
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

#### CFS

1. vruntime虚拟运行时间
2. 优先级越高，vruntime越小，CFS选取红黑树中当前CPU的就绪队列中最小vruntime的进程作为调度进程。

```c
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

#### 调度节拍

1. 
