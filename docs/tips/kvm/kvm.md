### Intel  VT  硬件虚拟化技术 ,在硬件级别上完成计算机的虚拟化. 为实现硬件虚拟化 ,VT增加了 12条新的 CPUVMX指令:
* VMCS控制 5 条:VMPTRLD VMPTRST VMCLEAR VMREAD VMWRITE 
* VMX命令 5条:VMLAUNCH VMCALL VMXON VMXOFF VMRESUME 
* Guest software 2条:INVEPT INVVPID 
* 基本操作的源代码在arch\x86\kvm\vmx.c中 （AMD cpu在svm.c中）


### VMCS 是一个4K的内存区域
* loaded_vmcs是一个虚拟机加载和退出的上下文，VMREAD VMWRITE 用于读写这些字段
```c
//vmx.c

struct vmcs_hdr {
	u32 revision_id:31;
	u32 shadow_vmcs:1;
};

struct vmcs {
	struct vmcs_hdr hdr;
	u32 abort;
	char data[];
};

DECLARE_PER_CPU(struct vmcs *, current_vmcs);

/*
 * vmcs_host_state tracks registers that are loaded from the VMCS on VMEXIT
 * and whose values change infrequently, but are not constant.  I.e. this is
 * used as a write-through cache of the corresponding VMCS fields.
 */
struct vmcs_host_state {
	unsigned long cr3;	/* May not match real cr3 */
	unsigned long cr4;	/* May not match real cr4 */
	unsigned long gs_base;
	unsigned long fs_base;
	unsigned long rsp;

	u16           fs_sel, gs_sel, ldt_sel;
#ifdef CONFIG_X86_64
	u16           ds_sel, es_sel;
#endif
};

struct vmcs_controls_shadow {
	u32 vm_entry;
	u32 vm_exit;
	u32 pin;
	u32 exec;
	u32 secondary_exec;
	u64 tertiary_exec;
};

/*
 * Track a VMCS that may be loaded on a certain CPU. If it is (cpu!=-1), also
 * remember whether it was VMLAUNCHed, and maintain a linked list of all VMCSs
 * loaded on this CPU (so we can clear them if the CPU goes down).
 */
struct loaded_vmcs {
	struct vmcs *vmcs;
	struct vmcs *shadow_vmcs;
	int cpu;
	bool launched;
	bool nmi_known_unmasked;
	bool hv_timer_soft_disabled;
	/* Support for vnmi-less CPUs */
	int soft_vnmi_blocked;
	ktime_t entry_time;
	s64 vnmi_blocked_time;
	unsigned long *msr_bitmap;
	struct list_head loaded_vmcss_on_cpu_link;
	struct vmcs_host_state host_state;
	struct vmcs_controls_shadow controls_shadow;
};
```

### KVM内核模块的初始化
```c
//virt\kvm\kvm_main.c

//kvm初始化的一些操作函数，
struct kvm_x86_init_ops {
	int (*cpu_has_kvm_support)(void);
	int (*disabled_by_bios)(void);
	int (*check_processor_compatibility)(void);
	int (*hardware_setup)(void);
	unsigned int (*handle_intel_pt_intr)(void);

	struct kvm_x86_ops *runtime_ops;
	struct kvm_pmu_ops *pmu_ops;
};
//在vmx_init_ops初始化时进行绑定
static struct kvm_x86_init_ops vmx_init_ops __initdata = {
	.cpu_has_kvm_support = cpu_has_kvm_support,
	.disabled_by_bios = vmx_disabled_by_bios,
	.check_processor_compatibility = vmx_check_processor_compat,
	.hardware_setup = hardware_setup,
	.handle_intel_pt_intr = NULL,

	.runtime_ops = &vmx_x86_ops, //在初始化的时候绑定到vmx相关的操作函数
	.pmu_ops = &intel_pmu_ops,  |
};                                  |
			            |
                                    |
static struct kvm_x86_ops vmx_x86_ops __initdata = {
	.name = "kvm_intel",
	.vcpu_run = vmx_vcpu_run,   //在这里注册vmx_vcpu_run,AMD是svm_vcpu_run
	.handle_exit = vmx_handle_exit, //从not-root态退出到root态的处理函数
..............
}

         kvm_init()                     ///初始化一些架构相关的数据结构
               ------>kvm_arch_init()---->kvm_init_msr_list()
                                     ------> kvm_timer_init(),
                                     ------>kvm_lapic_init()
                                    -------->kvm_alloc_emulator_cache()

              -------->kvm_arch_hardware_setup()--->hardware_setup()
                                                         ----->vmcs_config等全局变量的初始化
                                                        --->alloc_kvm_area()--->alloc_vmcs_cpu()//为每一个cpu分配vmcs空间
            ---------->misc_register(&kvm_dev);//在内核中注册kvm_dev字符设备
```


#### VM虚拟机的创建

```c
 
static struct file_operations kvm_chardev_ops = {
	.unlocked_ioctl = kvm_dev_ioctl,
	.llseek		= noop_llseek,
	KVM_COMPAT(kvm_dev_ioctl),
};

/*在编译内核的时候，如果开启Virtualization,则在/dev目录下创建一个
*名叫kvm的字符设备文件——kvm_dev(linux一切皆为文件) 
*/
static struct miscdevice kvm_dev = {
	KVM_MINOR,
	"kvm",
	&kvm_chardev_ops,
};

struct miscdevice  {
	int minor;
	const char *name;
	const struct file_operations *fops;
	struct list_head list;
	struct device *parent;
	struct device *this_device;
	const struct attribute_group **groups;
	const char *nodename;
	umode_t mode;
};
                            |----该函数申请kvm-vm文件，并赋值文件操作为————kvm_vm_fops
 ///kvm_dev_ioctl()--->kvm_dev_ioctl_create_vm()---->kvm_create_vm()
kvm_create_vm()
    ---------->kvm_arch_alloc_vm()//分配数据结构KVM的内存(intel是kvm_vmx, AMD是kvm_svm)
      /* KVM is pinned via open("/dev/kvm"), the fd passed to this ioctl(). */
   ---------->	__module_get(kvm_chardev_ops.owner);//owner是this_module也就是KVM
   ---------->kvm_arch_init_vm()//一些架构时钟等初始化
   --------->hardware_enable_all()--->hardware_enable_nolock()--->kvm_arch_hardware_enable()--->vmx_hardware_enable()
                                                                                                //调用架构相关的函数处理:打开VMX扩展模式cr4_set_bits(X86_CR4_VMXE);打开EPT扩展
  -------->kvm_coalesced_mmio_init()//初始化MMIO内存映射IO
  --------->list_add(&kvm->vm_list, &vm_list);加入到全局的vm_list中
```


#### vCPU的创建


```c

static const struct file_operations kvm_vm_fops = {
	.release        = kvm_vm_release,
	.unlocked_ioctl = kvm_vm_ioctl,
	.llseek		= noop_llseek,
	KVM_COMPAT(kvm_vm_compat_ioctl),
};

//kvm_vm_compat_ioctl()--->kvm_vm_ioctl()--->kvm_vm_ioctl_create_vcpu()

kvm_vm_ioctl_create_vcpu()
         ----->vcpu = kmem_cache_zalloc()//分配vcpu的内存
         ---->kvm_vcpu_init()//初始化vcpu结构体
         ---->kvm_arch_vcpu_create()//初始化arch
         ----->create_vcpu_fd()//之后创建vcpu文件,注册kvm_vcpu_fops,

static int create_vcpu_fd(struct kvm_vcpu *vcpu)
{
	char name[8 + 1 + ITOA_MAX_LEN + 1];

	snprintf(name, sizeof(name), "kvm-vcpu:%d", vcpu->vcpu_id);
	return anon_inode_getfd(name, &kvm_vcpu_fops, vcpu, O_RDWR | O_CLOEXEC);
}

kvm_make_request管理软件标志位的设置， 当准备进入vm-entry时将集中处理这些标志
```

#### vCPU的运行

```c

static const struct file_operations kvm_vcpu_fops = {
	.release        = kvm_vcpu_release,
	.unlocked_ioctl = kvm_vcpu_ioctl,
	.mmap           = kvm_vcpu_mmap,
	.llseek		= noop_llseek,
	KVM_COMPAT(kvm_vcpu_compat_ioctl),
};
kvm_vcpu_ioctl() //在kvm_vcpu_fops结构体中注册
    --->kvm_arch_vcpu_ioctl()
            ----->vcpu_load()//vcpu其实就是一个线程，当线程切换的时候需要重新加载vmcs
                      ------>preempt_notifier_register()//一种消息机制
	              ----->kvm_arch_vcpu_load() //对指定CPU的vmcs的加载,当vcpu VMLAUNCH，第一次运行时也需要vmcs

   ---->kvm_arch_vcpu_ioctl_run()
                 -----------------运行前的一些状态检查和
		                   |-------------一个死循环
                 -------------->vcpu_run()---->vcpu_enter_guest()
                                                        ---->kvm_mmu_reload(vcpu)-->kvm_mmu_load()//进入VM之前内存的准备，刷新TLB       
                                                                                 |-----kvm_x86_ops在该结构初始化的注册的函数 
                                                        ---->static_call(kvm_x86_prepare_switch_to_guest)(vcpu)-->vmx_prepare_switch_to_guest()//保存gs,fs等段选择子，以及MSR等信息
                                                        ---->exit_fastpath = static_call(kvm_x86_vcpu_run)(vcpu)--->vmx_vcpu_run()//run起来,一个死循环，只有exceptio才能退出处理exception
		                                       //调用退出处理函数vmx_handle_exit()，对退出原因进行处理
						        ---->r = static_call(kvm_x86_handle_exit)(vcpu, exit_fastpath); //返回一个r
                                                     /*当该众多的handler处理成功后，会得到一个大于0的返回值，而处理失败则会返回一个小于0的数；则又回到__vcpu_run()中的主循环中；
                                                        vcpu_enter_guest() > 0时： 则继续循环，再次准备进入not-root模式；
                                                       vcpu_enter_guest() <= 0时： 则跳出循环，返回root态，由Qemu根据退出原因进行处理。*/

		vmx_vcpu_run()
		    --->kvm_load_guest_xsave_state(vcpu)//设置guest的kvm_vcpu_arch信息,设置CR4寄存器--x86相关扩展标志位
		    --->pt_guest_enter(vmx);//一些MSR寄存器的切换(相关数据结构的数据切换准备) 从root态进入到not-root态

		   ----->__vmx_vcpu_run() ///汇编程序vmenter.S 真正做物理CPU寄存器切换的程序，让vcpu跑起来
		   
		   ---->pt_guest_exit(vmx);//退出,进入到root态
		   ---->kvm_load_host_xsave_state(vcpu);

static void pt_guest_enter(struct vcpu_vmx *vmx)
{
	if (vmx_pt_mode_is_system())
		return;

	/*
	 * GUEST_IA32_RTIT_CTL is already set in the VMCS.
	 * Save host state before VM entry.
	 */
	rdmsrl(MSR_IA32_RTIT_CTL, vmx->pt_desc.host.ctl);
	if (vmx->pt_desc.guest.ctl & RTIT_CTL_TRACEEN) {
		wrmsrl(MSR_IA32_RTIT_CTL, 0);
		pt_save_msr(&vmx->pt_desc.host, vmx->pt_desc.num_address_ranges);
		pt_load_msr(&vmx->pt_desc.guest, vmx->pt_desc.num_address_ranges);
	}
}

```

#### vCPU的退出

```c
vmx_handle_exit()
    ------->__vmx_handle_exit() 
                ------------>kvm_vmx_exit_handlers[exit_handler_index](vcpu);//调用VM-EXIT处理函数

//异常处理函数的注册
static int (*kvm_vmx_exit_handlers[])(struct kvm_vcpu *vcpu) = {
	[EXIT_REASON_EXCEPTION_NMI]           = handle_exception_nmi,
	[EXIT_REASON_EXTERNAL_INTERRUPT]      = handle_external_interrupt,
	[EXIT_REASON_TRIPLE_FAULT]            = handle_triple_fault,
	[EXIT_REASON_NMI_WINDOW]	      = handle_nmi_window,
	[EXIT_REASON_IO_INSTRUCTION]          = handle_io,
	[EXIT_REASON_CR_ACCESS]               = handle_cr,
	[EXIT_REASON_DR_ACCESS]               = handle_dr,
	[EXIT_REASON_CPUID]                   = kvm_emulate_cpuid,
	[EXIT_REASON_MSR_READ]                = kvm_emulate_rdmsr,
	[EXIT_REASON_MSR_WRITE]               = kvm_emulate_wrmsr,
	[EXIT_REASON_INTERRUPT_WINDOW]        = handle_interrupt_window,
	[EXIT_REASON_HLT]                     = kvm_emulate_halt,
	[EXIT_REASON_INVD]		      = kvm_emulate_invd,
	[EXIT_REASON_INVLPG]		      = handle_invlpg,
	[EXIT_REASON_RDPMC]                   = kvm_emulate_rdpmc,
	[EXIT_REASON_VMCALL]                  = kvm_emulate_hypercall,
	[EXIT_REASON_VMCLEAR]		      = handle_vmx_instruction,
	[EXIT_REASON_VMLAUNCH]		      = handle_vmx_instruction,
	[EXIT_REASON_VMPTRLD]		      = handle_vmx_instruction,
	[EXIT_REASON_VMPTRST]		      = handle_vmx_instruction,
	[EXIT_REASON_VMREAD]		      = handle_vmx_instruction,
	[EXIT_REASON_VMRESUME]		      = handle_vmx_instruction,
	[EXIT_REASON_VMWRITE]		      = handle_vmx_instruction,
	[EXIT_REASON_VMOFF]		      = handle_vmx_instruction,
	[EXIT_REASON_VMON]		      = handle_vmx_instruction,
	[EXIT_REASON_TPR_BELOW_THRESHOLD]     = handle_tpr_below_threshold,
	[EXIT_REASON_APIC_ACCESS]             = handle_apic_access,
	[EXIT_REASON_APIC_WRITE]              = handle_apic_write,
	[EXIT_REASON_EOI_INDUCED]             = handle_apic_eoi_induced,
	[EXIT_REASON_WBINVD]                  = kvm_emulate_wbinvd,
	[EXIT_REASON_XSETBV]                  = kvm_emulate_xsetbv,
	[EXIT_REASON_TASK_SWITCH]             = handle_task_switch,
	[EXIT_REASON_MCE_DURING_VMENTRY]      = handle_machine_check,
	[EXIT_REASON_GDTR_IDTR]		      = handle_desc,
	[EXIT_REASON_LDTR_TR]		      = handle_desc,
	[EXIT_REASON_EPT_VIOLATION]	      = handle_ept_violation,
	[EXIT_REASON_EPT_MISCONFIG]           = handle_ept_misconfig,
	[EXIT_REASON_PAUSE_INSTRUCTION]       = handle_pause,
	[EXIT_REASON_MWAIT_INSTRUCTION]	      = kvm_emulate_mwait,
	[EXIT_REASON_MONITOR_TRAP_FLAG]       = handle_monitor_trap,
	[EXIT_REASON_MONITOR_INSTRUCTION]     = kvm_emulate_monitor,
	[EXIT_REASON_INVEPT]                  = handle_vmx_instruction,
	[EXIT_REASON_INVVPID]                 = handle_vmx_instruction,
	[EXIT_REASON_RDRAND]                  = kvm_handle_invalid_op,
	[EXIT_REASON_RDSEED]                  = kvm_handle_invalid_op,
	[EXIT_REASON_PML_FULL]		      = handle_pml_full,
	[EXIT_REASON_INVPCID]                 = handle_invpcid,
	[EXIT_REASON_VMFUNC]		      = handle_vmx_instruction,
	[EXIT_REASON_PREEMPTION_TIMER]	      = handle_preemption_timer,
	[EXIT_REASON_ENCLS]		      = handle_encls,
	[EXIT_REASON_BUS_LOCK]                = handle_bus_lock_vmexit,
	[EXIT_REASON_NOTIFY]		      = handle_notify,
};
//异常处理函数数组的初始化
static const int kvm_vmx_max_exit_handlers =
	ARRAY_SIZE(kvm_vmx_exit_handlers);

```


#### vCPU的调度
```c

struct preempt_notifier;

/**
 * preempt_ops - notifiers called when a task is preempted and rescheduled
 * @sched_in: we're about to be rescheduled:
 *    notifier: struct preempt_notifier for the task being scheduled
 *    cpu:  cpu we're scheduled on
 * @sched_out: we've just been preempted
 *    notifier: struct preempt_notifier for the task being preempted
 *    next: the task that's kicking us out
 *
 * Please note that sched_in and out are called under different
 * contexts.  sched_out is called with rq lock held and irq disabled
 * while sched_in is called without rq lock and irq enabled.  This
 * difference is intentional and depended upon by its users.
 */
struct preempt_ops {
	void (*sched_in)(struct preempt_notifier *notifier, int cpu);
	void (*sched_out)(struct preempt_notifier *notifier,
			  struct task_struct *next);
};

      //在kvm_init()函数中被初始化
	kvm_preempt_ops.sched_in = kvm_sched_in;
	kvm_preempt_ops.sched_out = kvm_sched_out;

/**
 * preempt_notifier - key for installing preemption notifiers
 * @link: internal use
 * @ops: defines the notifier functions to be called
 *
 * Usually used in conjunction with container_of().
 */
struct preempt_notifier {
	struct hlist_node link;
	struct preempt_ops *ops;
};


kvm_vcpu_ioctl() //在kvm_vcpu_fops结构体中注册
    --->kvm_arch_vcpu_ioctl()
            ----->vcpu_load()//vcpu其实就是一个线程，当线程切换的时候需要重新加载vmcs
                      ------>preempt_notifier_register()//一种消息机制
	              ----->kvm_arch_vcpu_load() //对指定CPU的vmcs的加载,当vcpu VMLAUNCH，第一次运行时也需要vmcs
 //当满足条件时，调用kvm_sched_in()
kvm_sched_in()
  -------->kvm_arch_sched_in()---->调用vmx_x86_ops注册的vmx_shed_in()
            ---->vmx_sched_in()
	             ---->kvm_pause_in_guest()//暂停vcpu

 -------->kvm_arch_vcpu_load() //加载vmcs
         static_call(kvm_x86_vcpu_load)(vcpu, cpu)//注册vxm_vcpu_load()
	 ----->vmx_vcpu_load()
                   ----->vmx_vcpu_load_vmcs()
	 ------>设置vcpu的状态为KVM_REQ_STEAL_UPDATE



void vcpu_load(struct kvm_vcpu *vcpu)
{
	int cpu = get_cpu();

	__this_cpu_write(kvm_running_vcpu, vcpu);
	preempt_notifier_register(&vcpu->preempt_notifier);
	kvm_arch_vcpu_load(vcpu, cpu);
	put_cpu();
}
EXPORT_SYMBOL_GPL(vcpu_load);

```

#### kvm
1. 当Guest发起一次hypercall后，VMM会执行vmcall，导致的VM Exit,vmcall设置exit reason, VMM根据exit reason进行处理
2. vmcall为guest提供一种主动退出到root态的机制，比如需要发送IPI,主动调度等

```c
static inline long kvm_hypercall3(unsigned int nr, unsigned long p1,
				  unsigned long p2, unsigned long p3)
{
	long ret;

	if (cpu_feature_enabled(X86_FEATURE_TDX_GUEST))
		return tdx_kvm_hypercall(nr, p1, p2, p3, 0);

	asm volatile(KVM_HYPERCALL //宏,就是 vmcall指令
		     : "=a"(ret)
		     : "a"(nr), "b"(p1), "c"(p2), "d"(p3)
		     : "memory");
	return ret;
}


static int (*kvm_vmx_exit_handlers[])(struct kvm_vcpu *vcpu) = {
	[EXIT_REASON_VMCALL]                  = kvm_emulate_hypercall,	//调用处理函数
};

```
