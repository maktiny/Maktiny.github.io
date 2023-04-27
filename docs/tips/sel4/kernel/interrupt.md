### sel4的exception
1. 每个线程都有两个exception-handler endpoints, 
standard exceptionhandler and a timeout exception handler
2. 

#### sel4的中断数据结构
1. IRQ的类型
```c 
enum irq_state {
    IRQInactive  = 0,
    IRQSignal    = 1,
    IRQTimer     = 2,
#ifdef ENABLE_SMP_SUPPORT
    IRQIPI       = 3,
#endif
    IRQReserved
};

typedef word_t irq_state_t;

//中断状态表
irq_state_t intStateIRQTable[INT_STATE_ARRAY_SIZE];
/* CNode containing interrupt handler endpoints - like all seL4 objects, this CNode needs to be
 * of a size that is a power of 2 and aligned to its size. */
cte_t intStateIRQNode[BIT(IRQ_CNODE_SLOT_BITS)] ALIGN(BIT(IRQ_CNODE_SLOT_BITS + seL4_SlotBits));


enum x86_irq_state_tag {
    x86_irq_state_irq_free = 0,
    x86_irq_state_irq_ioapic = 1,
    x86_irq_state_irq_msi = 2,
    x86_irq_state_irq_reserved = 3
};
typedef enum x86_irq_state_tag x86_irq_state_tag_t;

struct x86_irq_state {
    uint32_t words[2];
};
typedef struct x86_irq_state x86_irq_state_t;

/* State data tracking what IRQ source is related to each
 * CPU vector */
//maxIRQ =  157 - 0x20
x86_irq_state_t x86KSIRQState[maxIRQ + 1];  

word_t x86KSAllocatedIOPorts[NUM_IO_PORTS / CONFIG_WORD_SIZE];
```

#### sel4中断的初始化
2. sel4在初始化的时候只设置IRQ Control capability, IRQHandler capability在之后用户空间通过seL4_IRQControl_GetIOAPIC(), seL4_IRQControl_GetMSI()设置
3. 现在sel4只支持IOAPIC和MSI中断,
```c 
init_irqs()
   --->setIRQState()
   --->Arch_irqStateInit()
   //提供一个IRQ Control capability
   --->write_slot(SLOT_PTR(pptr_of_cap(root_cnode_cap), seL4_CapIRQControl), cap_irq_control_cap_new());
```

#### sel4中断的处理
1. sel4的中断在内核中进行必要的处理之后,通过IPC把中断放到用户态来处理
```c 
//
#define INT_SAVE_STATE                              \
    push    %r11;                                   \
    /* skip FaultIP, RSP, Error, NextIP, RFLAGS */  \
    subq    $(5 * 8), %rsp;                         \
    push    %r15;                                   \
    push    %r9;                                    \
    push    %r8;                                    \
    push    %r10;                                   \
    push    %rdx;                                   \
    push    %r14;                                   \
    push    %r13;                                   \
    push    %r12;                                   \
    push    %rbp;                                   \
    push    %rbx;                                   \
    push    %rax;                                   \
    push    %rsi;                                   \
    push    %rdi

// "/src/arch/x86/64/traps.S"
BEGIN_FUNC(handle_interrupt)
    # push the rest of the registers
    INT_SAVE_STATE   //把中断现场压栈

    # switch to kernel stack
    LOAD_KERNEL_STACK //切换到内核栈

    # Set the arguments for c_x64_handle_interrupt
    movq    %rcx, %rdi
    movq    %rax, %rsi

    # gtfo to C land, we will not return
    call    c_x64_handle_interrupt    //跳转到c语言处理
END_FUNC(handle_interrupt)


enum exception {
    EXCEPTION_NONE,
    EXCEPTION_FAULT,
    EXCEPTION_LOOKUP_FAULT,
    EXCEPTION_SYSCALL_ERROR,
    EXCEPTION_PREEMPTED
};
typedef word_t exception_t;


struct seL4_Fault {
    uint64_t words[2];
};
typedef struct seL4_Fault seL4_Fault_t;

enum seL4_Fault_tag {
    seL4_Fault_NullFault = 0,
    seL4_Fault_CapFault = 1,
    seL4_Fault_UnknownSyscall = 2,
    seL4_Fault_UserException = 3,
    seL4_Fault_VMFault = 5
};
typedef enum seL4_Fault_tag seL4_Fault_tag_t;

c_x64_handle_interrupt() //设置一些内核ksCurThread当前线程的寄存器信息
   --->c_entry_hook() //进行fs,gs等段选择子的保存
       --->arch_c_entry_hook()
   --->c_handle_interrupt() //根据IRQ号的状态进行处理
        ---->handleFPUFault()//  irq == int_unimpl_dev : userland使用FPU,但是没有打开FPU支持,
               --->switchLocalFpuOwner() //lazy进行切换
                    --->enableFpu()
                    --->loadFpuState()

       ---->handleVMFaultEvent() //irq == int_page_fault(需要判断是指令错,还是数据错)
             --->handleVMFault()  //
                   ---->seL4_Fault_VMFault_new() //设置全局变量 seL4_Fault_t current_fault,返回exception_t 
             --->handleFault()
                  --->sendFaultIPC()
                       --->sendIPC() //将当前线程放到endpoint队列中
             --->schedule()//重新调度
       ---->handleUserLevelFault()  //irq < int_irq_min
            --->handleFault()
      --->handleInterruptEntry()  //likely(irq < int_trap_min)//主要的中断处理函数
          --->getActiveIRQ()
               --->receivePendingIRQ() //获取IRQ号
          --->handleInterrupt() //分为信号和时钟中断
               --->sendSignal()//设置信号对应的notification,如果notification绑定一个线程,则进行endpoint线程调度,然后处理
          --->timerTick()//更新时钟,然后进行调度
 --->restore_user_context()
      --->c_exit_hook() //从内核态返回用户态的fs,gs等寄存器的恢复
      //如果有pending interrupt,需要再次进入到内核
      //从系统调用和中断返回是不同的,需要分别处理
```

#### sel4的系统调用
1. sel4的系统调用有两种方式:
* 快路径: 使用RDX寄存器保存系统调用号,上下文保存和恢复的寄存器较少(快路径只支持SysCall 和SysReplyRecv两个系统调用)
* 慢路径: 使用RAX寄存器保存系统调用号(其他系统调用走慢路径)
```c 
BEGIN_FUNC(handle_fastsyscall)
    LOAD_KERNEL_AS(rsp)
    MAYBE_SWAPGS
    LOAD_USER_CONTEXT
    pushq   $-1             # set Error -1 to mean entry via syscall
    push    %rcx            # save NextIP
    push    %r11            # save RFLAGS
    push    %r15            # save R15 (message register)
    push    %r9             # save R9 (message register)
    push    %r8             # save R8 (message register)
    push    %r10            # save R10 (message register)
    push    %rdx            # save RDX (syscall number)
    push    %r14
    push    %r13
    push    %r12
    push    %rbp
    push    %rbx
    push    %rax
    push    %rsi            # save RSI (msgInfo register)
    push    %rdi            # save RDI (capRegister)

    # switch to kernel stack
    LOAD_KERNEL_STACK

    # RSI, RDI and RDX are already correct for calling c_handle_syscall
    # gtfo to C land, we will not return
#ifdef CONFIG_KERNEL_MCS
    # mov reply to correct register for calling c_handle_syscall
    movq   %r12, %rcx
#endif
    jmp    c_handle_syscall
END_FUNC(handle_fastsyscall)

enum syscall {
    SysCall = -1,
    SysReplyRecv = -2,
    SysSend = -3,
    SysNBSend = -4,
    SysRecv = -5,
    SysReply = -6,
    SysYield = -7,
    SysNBRecv = -8,

    .......
};

c_handle_syscall()
   --->c_entry_hook() //上下文保存
   --->fastpath_call()  //SysCall----具体如何处理没看明白
   --->fastpath_reply_recv(cptr, msgInfo) //SysReplyRecv
   --->slowpath()
       ---->handleSyscall() //根据不同的系统调用分别进行处理(具体如何处理就是sel4相关的查找capability, endpoint, 然后唤醒对应的线程)
            --->handleInterrupt() //SysSend, SysCall, SysNBRecv
            --->handleReply() //SysReply
            --->handleRecv() //SysNBRecv
            --->SysYield() //SysYield
            --->schedule();   //进行调度之后在切换到用户态
            --->activateThread();
       ---->restore_user_context() //进入用户态

//比如说handleReply()系统调用的处理(其他以后再看)
***********************handleReply()*********************
handleReply()  //用来回复syscall
  --->doReplyTransfer()
        --->caller = TCB_PTR(cap_reply_cap_get_capTCBPtr(callerCap))//找到send发送的线程
        --->doIPCTransfer() //
             --->sendBuffer = lookupIPCBuffer(false, sender);
             --->doNormalTransfer()
                  ---->copyMRs() //进行buffer信息的复制
        --->setThreadState(receiver, ThreadState_Running);
        --->possibleSwitchTo(receiver);//切换到replay的接收线程
  
????sle4的capability和TCB等查找,设置没看明白(果真sel4的设计思想没有领悟到)
```












