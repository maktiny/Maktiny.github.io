### seL4 x86_64的启动过程

#### seL4内核的入口
1.  sel4内核是静态链接成一个elf类型的文件kernel.elf 
```c 

//common_init直接设置CR0寄存器, 设置页表,进入long mode
BEGIN_FUNC(common_init)
    /* Disable paging. */
    movl %cr0, %eax
    andl $0x7fffffff, %eax
    movl %eax, %cr0

#ifdef CONFIG_FSGSBASE_INST
    call fsgsbase_enable
#endif /* CONFIG_FSGSBASE_INST */

    /* Initialize boot PML4 and switch to long mode. */
    call setup_pml4
    call enable_x64_mode
    lgdt _gdt64_ptr

#ifdef CONFIG_SYSCALL
    call syscall_enable
#endif

    ret
END_FUNC(common_init)


BEGIN_FUNC(_start)
    /* Assume we are MultiBooted, e.g. by GRUB.
     * While not immediately checked, the magic number is checked prior to 
     * Multiboot dependent operations. */
    movl %eax, %edi /* multiboot_magic    */
    movl %ebx, %esi /* multiboot_info_ptr */

    /* Load kernel boot stack pointer. */
    leal boot_stack_top, %esp

    /* Reset EFLAGS register (also disables interrupts etc.). */
    pushl $0    //这两条指令把EFLAGS寄存器置0, 关中断
    popf

    /* Already push parameters for calling boot_sys later. Push
     * them as 8 byte values so we can easily pop later. */
    pushl $0
    pushl %esi /* 2nd parameter: multiboot_info_ptr */
    pushl $0
    pushl %edi /* 1st parameter: multiboot_magic    */

    call common_init

    /* Reload CS with long bit to enable long mode. */
    ljmp $8, $_start64
END_FUNC(_start)

.code64
BEGIN_FUNC(_start64)
    /* Leave phys code behind and jump to the high kernel virtual address. */
    movabs $_entry_64, %rax
    jmp *%rax
END_FUNC(_start64)



BEGIN_FUNC(_entry_64)
    /* Update our stack pointer. */
    movq $0xffffffff80000000, %rax
    addq %rax, %rsp
    addq %rax, %rbp

    /* Pop the multiboot parameters off. */
    pop %rdi
    pop %rsi

    /* Load our real kernel stack. */
    leaq kernel_stack_alloc + (1 << CONFIG_KERNEL_STACK_BITS), %rsp

    movabs $restore_user_context, %rax
    push %rax
    jmp boot_sys   //基础的CPU寄存器环境设置完成, 跳转到c 代码boot_sys()执行
END_FUNC(_entry_64)
```

### sel4 x86_64的地址空间映射

```c 
// hardware.h
//其他架构的地址空间映射在 linker.lds文件中
/*
 *          2^64 +-------------------+
 *               | Kernel Page PDPT  | --+
 *   2^64 - 2^39 +-------------------+ PPTR_BASE  0xffffffff80000000
 *               |    TLB Bitmaps    |   |
 *               +-------------------+   |
 *               |                   |   |
 *               |     Unmapped      |   |
 *               |                   |   |
 *   2^64 - 2^47 +-------------------+   |
 *               |                   |   |
 *               |   Unaddressable   |   |
 *               |                   |   |
 *          2^47 +-------------------+ USER_TOP  0x7FFFFFFFFFFF 用户空间使用低地址
 *               |                   |   |
 *               |       User        |   |
 *               |                   |   |
 *           0x0 +-------------------+   |
 *                                       |
 *                         +-------------+
 *                         |
 *                         v
 *          2^64 +-------------------+
 *               |                   |
 *               |                   |     +------+      +------+
 *               |                   | --> |  PD  | -+-> |  PT  |
 *               |  Kernel Devices   |     +------+  |   +------+
 *               |                   |               |
 *               |                   |               +-> Log Buffer
 *               |                   |
 *   2^64 - 2^30 +-------------------+ KDEV_BASE 0xffffffffc0000000
 *               |                   |
 *               |                   |     +------+
 *               |    Kernel ELF     | --> |  PD  |
 *               |                   |     +------+
 *               |                   |
 *   2^64 - 2^29 +-------------------+ PPTR_TOP / KERNEL_ELF_BASE  0xffffffff80100000 内核的入口地址, .boot段的代码从这里开始映射
 *               |                   |
 *               |  Physical Memory  |
 *               |       Window      |
 *               |                   |
 *   2^64 - 2^39 +-------------------+ PPTR_BASE 0xffffffff80000000
 */

```
### sel4 x86_64内核的初始化
1. seL4内核把应用程序静态连接成ELF文件,加载到内存中运行(在内核启动的时候进行加载用户程序)
* sel4的物理内存使用mem_p_regs_t mem_p_regs这个数据结构描述(grub提供的物理内存信息, sel4初始化mem_p_regs结构体, sel就是调库侠)
```c 

typedef struct mem_p_regs {
    word_t count;
    p_region_t list[MAX_NUM_FREEMEM_REG];
} mem_p_regs_t;



typedef struct boot_state {
    p_region_t   avail_p_reg; /* region of available physical memory on platform */
    p_region_t   ki_p_reg;    /* region where the kernel image is in */
    ui_info_t    ui_info;     /* info about userland images */
    uint32_t     num_ioapic;  /* number of IOAPICs detected */
    paddr_t      ioapic_paddr[CONFIG_MAX_NUM_IOAPIC];
    uint32_t     num_drhu; /* number of IOMMUs */
    paddr_t      drhu_list[MAX_NUM_DRHU]; /* list of physical addresses of the IOMMUs */
    acpi_rmrr_list_t rmrr_list;
    acpi_rsdp_t  acpi_rsdp; /* copy of the rsdp */
    paddr_t      mods_end_paddr; /* physical address where boot modules end */
    paddr_t      boot_module_start; /* physical address of first boot module */
    uint32_t     num_cpus;    /* number of detected cpus */
    uint32_t     mem_lower;   /* lower memory size for boot code of APs to run in real mode */
    cpu_id_t     cpus[CONFIG_MAX_NUM_NODES];
    mem_p_regs_t mem_p_regs;  /* physical memory regions */   
    seL4_X86_BootInfo_VBE vbe_info; /* Potential VBE information from multiboot */
    seL4_X86_BootInfo_mmap_t mb_mmap_info; /* memory map information from multiboot */
    seL4_X86_BootInfo_fb_t fb_info; /* framebuffer information as set by bootloader */
} boot_state_t;

boot_sys()
----->try_boot_sys_mbi1() //内核获取boot_loader的信息,设置boot_state结构体
       ----->acpi_init()
----->try_boot_sys()
      --->x86_cpuid_initialize()//检查X86的CPU类型是否支持
      --->is_compiled_for_microarchitecture() //判断kernel镜像和内核是否兼容
      --->pic_remap_irqs() //建立PIC的中断信号和中断向量的映射
      --->try_boot_sys_node()
          --->map_kernel_window()
               --->pml4e_new() //设置x86_64的第一级页目录项
          --->setCurrentVSpaceRoot()//设置CR3寄存器
          --->init_cpu()     //sel4内核初始化最重要的两个函数,所有sel4概念的数据结构都在init_cpu, inti_sys_state中初始化
          --->init_sys_state()
      --->ioapic_init()
           ----->single_ioapic_init()
     ---->clh_lock_init() //coherent-FIFO lock 如果支持SMP,需要持有大内核锁(BKL),在linux2.0引入SMP和BKL,之后BKL向细粒度的spin lock过渡,BKL逐渐不再使用
     ---->start_boot_aps() //
---->schedule();
---->activateThread();
}
```
##### init_cpu函数主要设置x86_64架构相关的配置

```c 
init_cpu()
   ----->init_vm_state() //tss, gdt,idt
   ----->init_dtrs() //设置gdtr idtr(中断描述符表寄存器,存储中断描述符表的地址)
   ----->init_sysenter_msrs() //设置对应的一系列msr寄存器(sysenter和syscall是系统调用指令的不同版本)
   ----->init_syscall_msrs()
   ----->init_pat_msr() //pat(page attribute table) cache mode, 设置cache模式
   ----->init_ibrs() //设置IBRS 间接分支限制预测, 当前intel的IBRS硬件设计缺陷造成Meltdown漏洞,intel提交的linux补丁会造成内核性能下降
   ----->Arch_initFpu()//打开FPU支持  Enable FPU / SSE / SSE2 / SSE3 / SSSE3 / SSE4 Extensions.
   ----->apic_init()
```
* init_vm_state()函数设置任务状态段TSS, 全局表述符表, 中断描述符表等
```c 
BOOT_CODE bool_t init_vm_state(void)
{
       /*
     * Work around -Waddress-of-packed-member. TSS is the first thing
     * in the struct and so it's safe to take its address.
     */
    void *tss_ptr = &x86KSGlobalState[CURRENT_CPU_INDEX()].x86KStss.tss;
    init_tss(tss_ptr);
    init_gdt(x86KSGlobalState[CURRENT_CPU_INDEX()].x86KSgdt, tss_ptr);
    init_idt(x86KSGlobalState[CURRENT_CPU_INDEX()].x86KSidt);
    return true;
}


BOOT_CODE static void init_idt(idt_entry_t *idt)
{
    init_idt_entry(idt, 0x00, int_00);
    init_idt_entry(idt, 0x01, int_01);
 }
```
* init_dtrs()主要设置idtr等寄存器
```c 

BOOT_CODE void init_dtrs(void)
{
    /* When we install the gdt it will clobber any value of gs that
     * we have. Since we might be using it for TLS we can stash
     * and unstash any gs value using swapgs
     */
    swapgs();
    x64_install_gdt(&gdt_idt_ptr);
    swapgs();

    gdt_idt_ptr.limit = (sizeof(idt_entry_t) * (int_max + 1)) - 1;
    gdt_idt_ptr.base = (uint64_t)x86KSGlobalState[CURRENT_CPU_INDEX()].x86KSidt;
    x64_install_idt(&gdt_idt_ptr);

    x64_install_ldt(SEL_NULL); //使用对应的汇编语言,把地址加载到对应的寄存器

    x64_install_tss(SEL_TSS);
}
//machine_asm.S
BEGIN_FUNC(x64_install_gdt)
    lgdt    (%rdi)          # load gdtr with gdt pointer
    movw    $0x10, %ax      # load register ax with seg selector
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %ss
    movw    $0x0, %ax
    movw    %ax, %fs
    movw    %ax, %gs
    ret
END_FUNC(x64_install_gdt)

BEGIN_FUNC(x64_install_idt)
    lidt    (%rdi)
    ret
END_FUNC(x64_install_idt)

BEGIN_FUNC(x64_install_ldt)
    lldt    %di            // lldt指令把di中的地址加载到 ldtr寄存器中
    ret
END_FUNC(x64_install_ldt)

BEGIN_FUNC(x64_install_tss)
    ltr     %di
    ret
END_FUNC(x64_install_tss)
```

##### init_sys_state()函数开始构建sel4独有的capability相关的数据结构的初始化(sel4相关的结构体初始化,所有一整套体系开始构建)
1. sel4有一个根线程叫做rootserver
```c 
inti_sys_state()
  //做一些地址的转换
   --->arch_init_freemem()
        ---->init_freemem()
                ---->create_rootserver_objects() // 初始化rootserver_mem_t rootserver;从开始地址为rootserver的元素分配内存,这些元素就是sel4的root task
                      --->alloc_rootserver_obj()
                           ---->memzero()   //分配一段空间()把分配的空间置0
  --->create_root_cnode() //初始化root CNode结构
       ---->write_slot() //设置对应的标志位
  --->init_irqs() //初始化中断的状态,并提供IRQ control capabi1lity(具体没看懂)
      ---->setIRQState()
      ---->Arch_irqStateInit()
  ---->tsc_init() //TSC时间戳计数寄存器(随着CPU时钟自动增加),通过读取MSR获取时钟频率,然后计算
  ---->populate_bi_frame() //初始化seL4_BootInfo *bi 
  ---->create_it_address_space() //建立虚拟地址空间覆盖user image + ipc buffer and bootinfo frames (PML4 ,PDPT, PD, PT), 这中方式应该在libsel4被抽象成接口seL4_X86_PDPT_Map()
      ------->create_mapped_it_frame_cap()
             ----->map_it_frame_cap() //建立四级页表映射的函数
  ---->create_ipcbuf_frame_cap() //创建一个IPC bufer capability:seL4_CapInitThreadIPCBuffer, cap的地址映射同上
        ------->create_mapped_it_frame_cap()
             ----->map_it_frame_cap() //建立四级页表映射的函数
  ---->create_frames_of_region() //把剩余的userland image用户空间CNode的CSlot置空 /* create all userland image frames */
  ---->create_it_asid_pool()//创建两个capability: seL4_CapInitThreadASIDPool      seL4_CapIOPortControl       
 /* The top level ASID table */
 //asid_pool_t *x86KSASIDTable[BIT(asidHighBits)];
  ---->write_it_asid_pool() //把seL4_CapInitThreadASIDPool放入到x86KSASIDTable中
  ---->create_idle_thread()
  ---->create_initial_thread()
  ---->init_core_state() //通过宏NODE_STATE设置全局参数ksCurThread等
  ---->create_untypeds()// ndks_boot.bi_frame->untypedList[i]所有untyped的capability都存在这数组里
       // 所有的untyped不能超过CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS 50个
       //create_untypeds()把KERNEL_ELF_PADDR_BASE 0x100000之后的地址空间以及ndks_boot.freemem[i]都转化为ndks_boot.bi_frame->untypedList[i]
       //不清楚ndks_boot.reserved[] 和ndks_boot.freemem[]的用法和区别?????
       ---->create_untypeds_for_region()
             ---->provide_untyped_cap() //ndks_boot.bi_frame->untypedList[i]

  ---->bi_finalise() //更新 ndks_boot.bi_frame->empty,把CSpace中空间的CSlot组织起来
```
* 根据grub提供的信息,把分配的空闲物理内存组织起来(如何组织?还没看懂)
* boot_state 是全局变量, boot_state->mem_p_regs 管理sel4的全部物理内存
```c 

BOOT_BSS boot_state_t boot_state;

#define MAX_RESERVED 1
BOOT_BSS static region_t reserved[MAX_RESERVED];


#define MAX_NUM_FREEMEM_REG 16
typedef struct mem_p_regs {
    word_t count;
    p_region_t list[MAX_NUM_FREEMEM_REG];
} mem_p_regs_t;

try_boot_sys_mbi1()
   --->parse_mem_map() //根据grub提供的信息,把分配的空闲物理内存组织起来(如何组织?还没看懂)
       ---->add_mem_p_regs()
   --->或者add_mem_p_regs()

static BOOT_CODE bool_t add_mem_p_regs(p_region_t reg)
{
  //做一些内存的合法性检查

   printf("Adding physical memory region 0x%lx-0x%lx\n", reg.start, reg.end);
    boot_state.mem_p_regs.list[boot_state.mem_p_regs.count] = reg;
    boot_state.mem_p_regs.count++;
    return true;
}
```
4. init_freemem() 函数主要的工作就是初始化ndks_boot.freemem[i], freemem[]数组管理sel4所有的内存
* sle4的ndks_boot.slot_pos_cur指向最后一个使用的CSlot空间,在放置capability到CNode的时候,注意更新ndks_boot.slot_pos_cur(仅限于root CNode?还不清楚)
```c 

typedef struct seL4_BootInfo {
    seL4_Word         extraLen;        /* length of any additional bootinfo information */
    seL4_NodeId       nodeID;          /* ID [0..numNodes-1] of the seL4 node (0 if uniprocessor) */
    seL4_Word         numNodes;        /* number of seL4 nodes (1 if uniprocessor) */
    seL4_Word         numIOPTLevels;   /* number of IOMMU PT levels (0 if no IOMMU support) */
    seL4_IPCBuffer   *ipcBuffer;       /* pointer to initial thread's IPC buffer */
    seL4_SlotRegion   empty;           /* empty slots (null caps) */
    seL4_SlotRegion   sharedFrames;    /* shared-frame caps (shared between seL4 nodes) */
    seL4_SlotRegion   userImageFrames; /* userland-image frame caps */
    seL4_SlotRegion   userImagePaging; /* userland-image paging structure caps */
    seL4_SlotRegion   ioSpaceCaps;     /* IOSpace caps for ARM SMMU */
    seL4_SlotRegion   extraBIPages;    /* caps for any pages used to back the additional bootinfo information */
    seL4_Word         initThreadCNodeSizeBits; /* initial thread's root CNode size (2^n slots) */
    seL4_Domain       initThreadDomain; /* Initial thread's domain ID */
#ifdef CONFIG_KERNEL_MCS
    seL4_SlotRegion   schedcontrol; /* Caps to sched_control for each node */
#endif
    seL4_SlotRegion   untyped;         /* untyped-object caps (untyped caps) */
    seL4_UntypedDesc  untypedList[CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS]; /* information about each untyped */
    /* the untypedList should be the last entry in this struct, in order
     * to make this struct easier to represent in other languages */
} seL4_BootInfo;

typedef struct ndks_boot {
    p_region_t reserved[MAX_NUM_RESV_REG];
    word_t resv_count;
    region_t   freemem[MAX_NUM_FREEMEM_REG];
    seL4_BootInfo      *bi_frame;
    seL4_SlotPos slot_pos_cur;
} ndks_boot_t;

extern ndks_boot_t ndks_boot;
```
5. create_rootserver_objects()函数初始化rootserver_mem_t rootserver;从开始地址为rootserver的元素分配内存,这些元素就是sel4的root task
```c 

/* state tracking the memory allocated for root server objects */
typedef struct {
    pptr_t cnode;
    pptr_t vspace;
    pptr_t asid_pool;
    pptr_t ipc_buf;
    pptr_t boot_info;
    pptr_t extra_bi;
    pptr_t tcb;
#ifdef CONFIG_KERNEL_MCS
    pptr_t sc;
#endif
    region_t paging;
} rootserver_mem_t;

extern rootserver_mem_t rootserver;
```
##### CNode/capability的描述
1. CNode就是一个数组(一段空间), 每一个空间是CSlot, CSlot中存储的元素是capability.
```c 
--->create_root_cnode() //初始化root CNode结构
       ---->write_slot() //设置对应的标志位

struct cap {
    uint64_t words[2];
};
typedef struct cap cap_t;

struct cte {
    cap_t cap;
    mdb_node_t cteMDBNode;
};
typedef struct cte cte_t;

typedef cte_t *slot_ptr_t;
//sel4的所有的capability
enum cap_tag {
    cap_null_cap = 0,
    cap_untyped_cap = 2,
    cap_endpoint_cap = 4,
    cap_notification_cap = 6,
    cap_reply_cap = 8,
    cap_cnode_cap = 10,
    cap_thread_cap = 12,
    cap_irq_control_cap = 14,
    cap_irq_handler_cap = 16,
    cap_zombie_cap = 18,
    cap_domain_cap = 20,
    cap_frame_cap = 1,
    cap_page_table_cap = 3,
    cap_page_directory_cap = 5,
    cap_pdpt_cap = 7,
    cap_pml4_cap = 9,
    cap_asid_control_cap = 11,
    cap_asid_pool_cap = 13,
    cap_io_port_cap = 19,
    cap_io_port_control_cap = 31
};
typedef enum cap_tag cap_tag_t;

//在root CNode中capability的顺序是固定的
/* caps with fixed slot positions in the root CNode */
enum {
    seL4_CapNull                =  0, /* null cap */
    seL4_CapInitThreadTCB       =  1, /* initial thread's TCB cap */
    seL4_CapInitThreadCNode     =  2, /* initial thread's root CNode cap */
    seL4_CapInitThreadVSpace    =  3, /* initial thread's VSpace cap */
    seL4_CapIRQControl          =  4, /* global IRQ controller cap */
    seL4_CapASIDControl         =  5, /* global ASID controller cap */
    seL4_CapInitThreadASIDPool  =  6, /* initial thread's ASID pool cap */
    seL4_CapIOPortControl       =  7, /* global IO port control cap (null cap if not supported) */
    seL4_CapIOSpace             =  8, /* global IO space cap (null cap if no IOMMU support) */
    seL4_CapBootInfoFrame       =  9, /* bootinfo frame cap */
    seL4_CapInitThreadIPCBuffer = 10, /* initial thread's IPC buffer frame cap */
    seL4_CapDomain              = 11, /* global domain controller cap */
    seL4_CapSMMUSIDControl      = 12,  /*global SMMU SID controller cap, null cap if not supported*/
    seL4_CapSMMUCBControl       = 13,  /*global SMMU CB controller cap, null cap if not supported*/
#ifdef CONFIG_KERNEL_MCS
    seL4_CapInitThreadSC        = 14, /* initial thread's scheduling context cap */
    seL4_NumInitialCaps         = 15
#else
    seL4_NumInitialCaps         = 14
#endif /* !CONFIG_KERNEL_MCS */
};

```

##### sel4中idle()和init()线程的创建
1. 线程相关的数据结构
```c
/* X86 FPU context. */
struct user_fpu_state {
    uint8_t state[CONFIG_XSAVE_SIZE];
};
typedef struct user_fpu_state user_fpu_state_t;

/* X86 user-code context */
struct user_context {
    user_fpu_state_t fpuState;
    word_t registers[n_contextRegisters];
#if defined(ENABLE_SMP_SUPPORT) && defined(CONFIG_ARCH_IA32)
    /* stored pointer to kernel stack used when kernel run in current TCB context. */
    word_t kernelSP;
#endif
#ifdef CONFIG_HARDWARE_DEBUG_API
    user_breakpoint_state_t breakpointState;
#endif
};
typedef struct user_context user_context_t;

typedef struct arch_tcb {
    user_context_t tcbContext;
#ifdef CONFIG_VTX
    /* Pointer to associated VCPU. NULL if not associated.
     * tcb->tcbVCPU->vcpuTCB == tcb. */
    struct vcpu *tcbVCPU;
#endif /* CONFIG_VTX */
} arch_tcb_t;

struct thread_state {
    uint64_t words[3];
};
typedef struct thread_state thread_state_t;

struct tcb {
    /* arch specific tcb state (including context)*/
    arch_tcb_t tcbArch;

    /* Thread state, 3 words */
    thread_state_t tcbState;

    /* Notification that this TCB is bound to. If this is set, when this TCB waits on
     * any sync endpoint, it may receive a signal from a Notification object.
     * 1 word*/
    notification_t *tcbBoundNotification;

    /* Current fault, 2 words */
    seL4_Fault_t tcbFault;

    /* Current lookup failure, 2 words */
    lookup_fault_t tcbLookupFailure;

    /* Domain, 1 byte (padded to 1 word) */
    dom_t tcbDomain;

    /*  maximum controlled priority, 1 byte (padded to 1 word) */
    prio_t tcbMCP;

    /* Priority, 1 byte (padded to 1 word) */
    prio_t tcbPriority;

#ifdef CONFIG_KERNEL_MCS
    /* scheduling context that this tcb is running on, if it is NULL the tcb cannot
     * be in the scheduler queues, 1 word */
    sched_context_t *tcbSchedContext;

    /* scheduling context that this tcb yielded to */
    sched_context_t *tcbYieldTo;
#else
    /* Timeslice remaining, 1 word */
    word_t tcbTimeSlice;

    /* Capability pointer to thread fault handler, 1 word */
    cptr_t tcbFaultHandler;
#endif

    /* userland virtual address of thread IPC buffer, 1 word */
    word_t tcbIPCBuffer;

#ifdef ENABLE_SMP_SUPPORT
    /* cpu ID this thread is running on, 1 word */
    word_t tcbAffinity;
#endif /* ENABLE_SMP_SUPPORT */

    /* Previous and next pointers for scheduler queues , 2 words */
    struct tcb *tcbSchedNext;
    struct tcb *tcbSchedPrev;
    /* Preivous and next pointers for endpoint and notification queues, 2 words */
    struct tcb *tcbEPNext;
    struct tcb *tcbEPPrev;

#ifdef CONFIG_BENCHMARK_TRACK_UTILISATION
    /* 16 bytes (12 bytes aarch32) */
    benchmark_util_t benchmark;
#endif
};
typedef struct tcb tcb_t;



enum _register {
    // User registers that will be preserved during syscall
    // Deliberately place the cap and badge registers early
    // So that when popping on the fastpath we can just not
    // pop these
    RDI                     = 0,    /* 0x00 */
    capRegister             = 0,
    badgeRegister           = 0,
    RSI                     = 1,    /* 0x08 */
    msgInfoRegister         = 1,
    RAX                     = 2,    /* 0x10 */
    RBX                     = 3,    /* 0x18 */
    RBP                     = 4,    /* 0x20 */
    R12                     = 5,    /* 0x28 */
#ifdef CONFIG_KERNEL_MCS
    replyRegister           = 5,
#endif
    R13                     = 6,    /* 0x30 */
#ifdef CONFIG_KERNEL_MCS
    nbsendRecvDest          = 6,
#endif
    R14                     = 7,    /* 0x38 */
    RDX                     = 8,    /* 0x40 */
    // Group the message registers so they can be efficiently copied
    R10                     = 9,    /* 0x48 */
    R8                      = 10,   /* 0x50 */
    R9                      = 11,   /* 0x58 */
    R15                     = 12,   /* 0x60 */
    FLAGS                   = 13,   /* 0x68 */
    // Put the NextIP, which is a virtual register, here as we
    // need to set this in the syscall path
    NextIP                  = 14,   /* 0x70 */
    // Same for the error code
    Error                   = 15,   /* 0x78 */
    /* Kernel stack points here on kernel entry */
    RSP                     = 16,   /* 0x80 */
    FaultIP                 = 17,   /* 0x88 */
    // Now user Registers that get clobbered by syscall
    R11                     = 18,   /* 0x90 */
    RCX                     = 19,   /* 0x98 */
    CS                      = 20,   /* 0xa0 */
    SS                      = 21,   /* 0xa8 */
    n_immContextRegisters   = 22,   /* 0xb0 */

    // For locality put these here as well
    FS_BASE                 = 22,   /* 0xb0 */
    TLS_BASE                = FS_BASE,
    GS_BASE                 = 23,   /* 0xb8 */

    n_contextRegisters      = 24    /* 0xc0 */
};
```
2. idle线程的创建,和linux一样SMP,每个核有一个idle线程
```c 
create_idle_thread()
 ---->configureIdleThread(tcb_t *tcb)
        --->Arch_configureIdleThread(tcb);
             --->setRegister(tcb, NextIP, (word_t)&idle_thread); //将NextIP虚拟寄存器填充idle_thread裸函数的入口地址
        --->setThreadState(tcb, ThreadState_IdleThreadState);
             --->thread_state_ptr_set_tsType(&tptr->tcbState, ts); //将线程的状态设置成ThreadState_IdleThreadState
             --->scheduleTCB(tptr);
                  --->rescheduleRequired()
                       ---->tcbSchedEnqueue()//通过宏SCHED_ENQUEUE()调用tcbSchedEnqueue(), 将ilde的TCB加入到调度队列中
}

__attribute__((naked)) NORETURN void idle_thread(void)
{
    /* We cannot use for-loop or while-loop here because they may
     * involve stack manipulations (the compiler will not allow
     * them in a naked function anyway). */
    asm volatile(
        "1: hlt\n"
        "jmp 1b"
    );
}
```
3. init()线程的创建

```c 
create_initial_thread()
   ---->Arch_initContext()
        ---->Mode_initContext() //把GPR全部设置为0
        ---->Arch_initFpuContext() //设置FPU的支持
   ---->cteInsert() //初始化TCB相关的结构,将seL4_CapInitThreadCNode, seL4_CapInitThreadVSpace,seL4_CapInitThreadIPCBuffer插入到rootserver.tcb对应的位置
   ---->setNextPC(tcb, ui_v_entry); //设置为用户态的elf文件的entry(elf文件结构体的entry元素),init()直接执行用户态程序
   ---->configure_sched_context()
         --->refill_new(tcb->tcbSchedContext, MIN_REFILLS, timeslice, 0)//为该线程赋予时间片
   ---->setupReplyMaster() //获取或者创建一个reply capability
   ---->setThreadState()
         --->thread_state_ptr_set_tsType(&tptr->tcbState, ts); //将线程的状态设置成ThreadState_Running
         --->scheduleTCB(tptr);
                  --->rescheduleRequired()
                       ---->tcbSchedEnqueue()//通过宏SCHED_ENQUEUE()调用tcbSchedEnqueue(), 将ilde的TCB加入到调度队列中
   ---->cap_thread_cap_new() //创建seL4_CapInitThreadTCB
   ---->cap_sched_context_cap_new()//如果打开MSC ,需要创建seL4_CapInitThreadSC
```


#### sel4线程的调度
1. 当打开MCS,线程调度才打开.相关的数据结构
2. scheduling context通过IPC在线程中传递(seL4_Call(), seL4_NBSendRecv()),
3. sel4的线程优先级0-255,rootserver的优先级是255, 普通线程优先级不能超过MCP
   创建的新线程,如果不设置线程优先级则默认为0
```c 

struct tcb_queue {
    tcb_t *head;
    tcb_t *end;
};
typedef struct tcb_queue tcb_queue_t;


typedef struct refill {
    /* Absolute timestamp from when this refill can be used */
    ticks_t rTime;
    /* Amount of ticks that can be used from this refill */
    ticks_t rAmount;
} refill_t;

#define MIN_REFILLS 2u

struct sched_context {
    /* period for this sc -- controls rate at which budget is replenished */
    ticks_t scPeriod;

    /* amount of ticks this sc has been scheduled for since seL4_SchedContext_Consumed
     * was last called or a timeout exception fired */
    ticks_t scConsumed;

    /* core this scheduling context provides time for - 0 if uniprocessor */
    word_t scCore;

    /* thread that this scheduling context is bound to */
    tcb_t *scTcb;

    /* if this is not NULL, it points to the last reply object that was generated
     * when the scheduling context was passed over a Call */
    reply_t *scReply;

    /* notification this scheduling context is bound to */
    notification_t *scNotification;

    /* data word that is sent with timeout faults that occur on this scheduling context */
    word_t scBadge;

    /* thread that yielded to this scheduling context */
    tcb_t *scYieldFrom;

    /* Amount of refills this sc tracks */
    word_t scRefillMax;
    /* Index of the head of the refill circular buffer */
    word_t scRefillHead;
    /* Index of the tail of the refill circular buffer */
    word_t scRefillTail;

    /* Whether to apply constant-bandwidth/sliding-window constraint
     * rather than only sporadic server constraints */
    bool_t scSporadic;
};

struct reply {
    /* TCB pointed to by this reply object. This pointer reflects two possible relations, depending
     * on the thread state.
     *
     * ThreadState_BlockedOnReply: this tcb is the caller that is blocked on this reply object,
     * ThreadState_BlockedOnRecv: this tcb is the callee blocked on an endpoint with this reply object.
     *
     * The back pointer for this TCB is stored in the thread state.*/
    tcb_t *replyTCB;

    /* 0 if this is the start of the call chain, or points to the
     * previous reply object in a call chain */
    call_stack_t replyPrev;

    /* Either a scheduling context if this reply object is the head of the call chain
     * (the last caller before the server) or another reply object. 0 if no scheduling
     * context was passed along the call chain */
    call_stack_t replyNext;

    /* Unused, explicit padding to make struct size the correct power of 2. */
    word_t padding;
};
#endif
```
##### sel4 线程调度流程
* sel4在调度之前把当前线程也加入到调度队列中
* sel4只提供最基本的调度设置,调度算法需要在用户态自己实现,然后通过IPC,调用scheduling context实现调度
* sel4支持域调度,当线程所处的域是active,线程才能调度.
* sel4的域是在编译是静态确定的,跨域之间的IPC需要等到域切换才能实现.跨域进行seL4_Yield()不行
```c 

boot_sys()
  --->schedule()  //上下文如何切换???   优先级如何计算????
        --->isSchedulable()//宏,实际调用isRunnable(), 当线程状态为ThreadState_Running, ThreadState_Restart时,将该线程放入到调度队列中
        --->SCHED_ENQUEUE_CURRENT_TCB //宏,实际调用tcbSchedEnqueue()加入调度队列
        --->scheduleChooseNewThread()
             ---->chooseThread() 
                  --->getHighestPrio()//sel4是硬实时系统,每次选取最高优先级的线程来调度(sel4提供的线程优先级是固定的),优先级计算还没搞明白?????????,根据优先级来索引线程(调度队列就是一个链表)
                  --->switchToThread()
                       --->Arch_switchToThread(thread)//一些MSR寄存器的设置,架构相关,可能需要看intel手册
                            ---->setVMRoot()//设置CR3为调度到的线程地址空间
                            //如果支持SMP,则需要设置tcb->tcbArch.tcbContext.registers,没有看到保存上下文的代码???????????????????,不明白,应该就是那段内联汇编代码
                            ---->x86_ibpb()
                            ---->x86_flush_rsb()
                       --->tcbSchedDequeue(thread)//将调度到的线程从调度队列中删除(链表节点删除)
                       --->NODE_STATE(ksCurThread) = thread; //将全局变量ksCurThread设置为调度到的线程
                  --->switchToIdleThread()//如果没有线程可以调度,则调度idle线程
                      --->Arch_switchToIdleThread()
                        //如果支持SMP,则需要设置tcb->tcbArch.tcbContext.registers
                           ---->setVMRoot()
  --->activateThread()//设置PC和线程状态
      --->setNextPC(NODE_STATE(ksCurThread), pc);
      --->setThreadState(NODE_STATE(ksCurThread), ThreadState_Running);
        
```
























