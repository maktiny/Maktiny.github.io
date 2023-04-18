### sel4内核的单独编译
1. 在sel4的根目录下新建build
```bash
 mkdir build
 
 //如果需要编译其他的平台的,换X64_verified.cmake, 如果需要交叉编译https://docs.sel4.systems/projects/buildsystem/using.html
 cmake -DCROSS_COMPILER_PREFIX= -DCMAKE_TOOLCHAIN_FILE=../gcc.cmake -G Ninja -C 
 ../configs/X64_verified.cmake ../

 bear -- ninja

 mv compile_commands.json ../    //把compile_commands.json移交到sel4的根目录

```

### sle4的tutorial的编译

```bash
  repo init -u https://github.com/seL4/sel4-tutorials-manifest
  repo sync


  mkdir tutorial
  cd tutorial
   //更换capabilities即可
 ./init --tut capabilities --solution
 
 cd capabilities_build
 
 ninja
```

### 调试用户程序
1. 由于是使用qemu
```bash
   terminal 1: ./simulate
   
   terminal 2: ./launch_gdb
```

### 调试sle4内核
1. 内核image的boot_loader阶段的过程没办法gdb,此时的地址是物理地址,gdb不支持该阶段的调试
```bash
   terminal 1:  ./simulate --extra-qemu-args="-S -s"
   
   terminal 2:  gdb kernel/kernel_elf
                target remote:1234
```
2. sle4内核支持debug输出
```bash 
__builtin_return_address() (to figure out stack traces).

In the kernel, we provide debug_printKernelEntryReason found in debug.h which can be used at any point in the kernel to output the current operation that the kernel is doing.
```
3. [官网的gdb支持](https://docs.sel4.systems/projects/sel4-tutorials/debugging-guide.html)


### sel4 test的测试样列
```bash 

   repo init -u https://github.com/seL4/sel4test-manifest.git
   repo sync

   mkdir build
   cd build
   
   ../init-build.sh -DPLATFORM=x86_64 -DSIMULATION=TRUE
   ninja

```

### Gprof是Linux下一个强有力的程序分析工具
```bash 
//编译时候加编译参数" -pg  "
   gcc –o test –pg test.c 
//编译生成一个文件gmon.out，这就是gprof生成的文件，保存有程序运行期间函数调用等信息。

//最后，用gprof命令查看gmon.out保存的信息：
   gprof test gmon.out –b
```



### seL4内核相关的部分
### sel4内核内存分配
1. libsel4是sel4内核的依赖库函数, 就像glibc对于linux一样
2. sle4不支持动态分配内存,所有的内存都在sel4内核初始化的时候静态绑定为untyped capabilities,存在untypedList数组中,
 需要时候使用seL4_Untyped_Retype()分配,seL4_CNode_Revoke()释放 ------->seL4内存的分配和释放管理
3. 其他架构相关的数据, seL4_BootInfo不能描述的放在seL4_BootInfoHeader结构体中 
```c
/*
 1. libsel4/include/sel4/bootinfo_types.h
*/
//seL4的内核object, 内存分配需要指定常object
        case seL4_TCBObject:
        case seL4_EndpointObject:
        case seL4_NotificationObject:
        case seL4_CapTableObject:
        case seL4_UntypedObject:
        case seL4_SchedContextObject:
        case seL4_ReplyObject:


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


/* If extraLen > 0, then 4K after the start of bootinfo there is a region of the
 * size extraLen that contains additional boot info data chunks. They are
 * arch/platform specific and may or may not exist in any given execution. Each
 * chunk has a header that contains an ID to describe the chunk. All IDs share a
 * global namespace to ensure uniqueness.
 */
typedef enum {
    SEL4_BOOTINFO_HEADER_PADDING            = 0,
    SEL4_BOOTINFO_HEADER_X86_VBE            = 1,
    SEL4_BOOTINFO_HEADER_X86_MBMMAP         = 2,
    SEL4_BOOTINFO_HEADER_X86_ACPI_RSDP      = 3,
    SEL4_BOOTINFO_HEADER_X86_FRAMEBUFFER    = 4,
    SEL4_BOOTINFO_HEADER_X86_TSC_FREQ       = 5, /* frequency is in MHz */
    SEL4_BOOTINFO_HEADER_FDT                = 6, /* device tree */
    /* Add more IDs here, the two elements below must always be at the end. */
    SEL4_BOOTINFO_HEADER_NUM,
    SEL4_FORCE_LONG_ENUM(seL4_BootInfoID)
} seL4_BootInfoID;

/* Common header for all additional bootinfo chunks to describe the chunk. */
typedef struct seL4_BootInfoHeader {
    seL4_Word id;  /* identifier of the following blob */
    seL4_Word len; /* length of the chunk, including this header */
} seL4_BootInfoHeader;

```

### seL4内核capability的使用
1. root task 也有一个 CSpace， 在 boot 阶段被设置，包含了被 seL4 管理的所有资源的 capability
2. 其他 capability 有 seL4_BootInfo 这个数据结构来描述。 seL4_BootInof 描述了初始的所有 capability的范围，包括了初始的 CSpace 中的可用的 Slot 
```c

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

3. CSpace空间有多个CNode对象，CNode对象是一个数组，数组中的各个位置我们称为 CSlots, 数组里的元素是 capability
4. Slot有两个状态: empty / full,  CNode有 1 << CNodeSizeBits个Slot, Slot占 1 << seL4_SlotBits个字节
```c
CSpace
-------------------------------------------------------
CNode  |----|-------|-----------|
       |    |       | CSlot     |
       |----|-------|-----------|

CNode  |----|-------|-----------|
       |    |       |           |
       |----|-------|-----------|

CNode  |----|-------|-----------|
       |    |       |           |
       |----|-------|-----------|
-------------------------------------------------------

/sel4/include/object/structures.h
// A diagram of a TCB kernel object that is created from untyped:
//  _______________________________________
// |     |             |                   |
// |     |             |                   |
// |cte_t|   unused    |       tcb_t       |
// |     |(debug_tcb_t)|                   |
// |_____|_____________|___________________|
// 0     a             b                   c
// a = tcbCNodeEntries * sizeof(cte_t)
// b = BIT(TCB_SIZE_BITS)
// c = BIT(seL4_TCBBits)

/* Capability table entry (CTE) */
struct cte {
    cap_t cap;
    mdb_node_t cteMDBNode;
};
typedef struct cte cte_t;


/* Thread state */
enum _thread_state {
    ThreadState_Inactive = 0,
    ThreadState_Running,
    ThreadState_Restart,
    ThreadState_BlockedOnReceive,
    ThreadState_BlockedOnSend,
    ThreadState_BlockedOnReply,
    ThreadState_BlockedOnNotification,
#ifdef CONFIG_VTX
    ThreadState_RunningVM,
#endif
    ThreadState_IdleThreadState
};
typedef word_t _thread_state_t;



/* TCB: size >= 18 words + sizeof(arch_tcb_t) + 1 word on MCS (aligned to nearest power of 2) */
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
```

### seL4内核虚实地址的映射
1. seL4 不提供除简单的硬件页表机制外的其他虚拟内存管理，用户态必须自己创建中间分页结构、映射、和取消映射的服务
2. 对象VSpace 是程序的虚拟地址空间，VSpace的 capability 被存放在 seL4_CapInitThreadVSpace 这个 Slot 中
3. 不同的架构有不同的页表, X86_64有四级页表,其中VSpace表示PML4,也就是顶级页表目录项.
![](https://drive.google.com/uc?export=view&id=1S9dFoKvzS5nbWmdfK8bcr5467Y71_O96)
4. 如果给定的地址没有对齐， seL4 会根据页大小自动对齐
5. 创建页表结构
```c 

    seL4_BootInfo *info = platsupport_get_bootinfo();
    seL4_Error error;
    //libsel4库提供的分配CNode的capability的接口
    seL4_CPtr frame = alloc_object(info, seL4_X86_4K, 0);
    seL4_CPtr pdpt = alloc_object(info, seL4_X86_PDPTObject, 0);
    seL4_CPtr pd = alloc_object(info, seL4_X86_PageDirectoryObject, 0);
    seL4_CPtr pt = alloc_object(info, seL4_X86_PageTableObject, 0);

     //创建页表结构,并映射虚拟内存
    /* map a PDPT at TEST_VADDR */
    error = seL4_X86_PDPT_Map(pdpt, seL4_CapInitThreadVSpace, TEST_VADDR, seL4_X86_Default_VMAttributes);
    //PD
    error = seL4_X86_PageDirectory_Map(pd, seL4_CapInitThreadVSpace, TEST_VADDR, seL4_X86_Default_VMAttributes);
    assert(error == seL4_NoError);
    //PT
    error = seL4_X86_PageTable_Map(pt, seL4_CapInitThreadVSpace, TEST_VADDR, seL4_X86_Default_VMAttributes);
    assert(error == seL4_NoError);

```
6. 一旦为特定的虚拟地址映射了中间的页目录项结构，就可以调用一些seL4_X86_Page_Map()将物理页映射到该虚拟地址范围
```c
//seL4_CanRead 设置页的属性
 error = seL4_X86_Page_Map(frame, seL4_CapInitThreadVSpace, TEST_VADDR, seL4_CanRead, seL4_X86_Default_VMAttributes);
    if (error == seL4_FailedLookup) {
        printf("Missing intermediate paging structure at level %lu\n", seL4_MappingFailedLookupLevel());
    }
```
7. eL4_MappingFailedLookupLevel 函数可以用于检测哪一级的分页结构没有被设置。如果要多次映射一个物理帧（共享内存等应用），
必须复制帧对应的 capability ，也就是说一个 capability 只能对应一个映射






















