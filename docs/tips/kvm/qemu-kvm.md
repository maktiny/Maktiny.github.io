### kvm虚拟化
* kvm只是提供硬件的虚拟化支持，向上层的应用提供接口，虚拟出来的vcpu, vm(虚拟机)等都是内存中的一个数据结构(也就是文件句柄)。
* 虚拟机通过ioctl()系统调用与内核交流，所有的指令都能被ioctl截获。
* qemu-kvm底层通过使用kvm的接口实现虚拟化,而qemu使用TCG二进制翻译(guest instruction --> host instruction)的方式实现虚拟化
* QEMU将KVM整合了进来，通过/ioctl 调用 /dev/kvm，从而将CPU指令的部分交给内核模块来做，KVM实现了CPU和内存的虚拟化，
但kvm不能虚拟其他硬件设备，因此qemu还有模拟IO设备（磁盘，网卡，显卡等）的作用，KVM加上QEMU后就是完整意义上的服务器虚拟化
* QEMU-KVM具有两大作用：1.提供对cpu，内存（KVM负责），IO设备（QEMU负责）的虚拟 2.对各种虚拟设备的创建，调用进行管理（QEMU负责
* 由于qemu模拟io设备效率不高的原因，现在常常采用半虚拟化的virtio方式来虚拟IO设备
* qemu-kvm如果不支持kvm,则使用tcg
```c

void qemu_init_vcpu(void *_env)
{
    CPUArchState *env = _env;

    env->nr_cores = smp_cores;
    env->nr_threads = smp_threads;
    env->stopped = 1;
    if (kvm_enabled()) {
        qemu_kvm_start_vcpu(env);
    } else if (tcg_enabled()) {
        qemu_tcg_init_vcpu(env);
    } else {
        qemu_dummy_start_vcpu(env);
    }
}


```


### qemu-kvm的执行流程
* 
```c
// vl.c的main函数是qemu-kvm的主要流程

 --->main //解析运行参数，调用相应的接口
   ------->module_call_init() //初始化一些qemu的QOM,block等
   ------->configure_accelerator()//该函数调用accel_list中注册的kvm_init()
   ------->cpudef_init()---->cpudef_setup()--->x86_cpudef_setup()--->static x86_def_t builtin_x86_defs[] //选取这个数组中定义的CPU模型
   ------->QEMUMachine *current_machine = NULL; //qemu在main函数中初始化一个QEMUMachine的数据结构，也就是表示一个虚拟机
           machine->init(ram_size, boot_devices,kernel_filename, kernel_cmdline, initrd_filename, cpu_model);//通过QEMUMachine的初始化函数申请虚拟机的内存，注册vCPU绑定的线程
           //注册的初始化函数init()即为pc_init_pci()

   -------->vm_start()//通过广播的方式设置所有的cpu状态为running

```

* module_call_init函数的机制--把初始化函数注册到一给个链表中，遍历链表执行初始化module_init()函数。
```c
//module.h
#define module_init(function, type)                                         \
static void __attribute__((constructor)) do_qemu_init_ ## function(void) {  \
    register_module_init(function, type);                                   \
}

typedef enum {
    MODULE_INIT_BLOCK,
    MODULE_INIT_MACHINE,
    MODULE_INIT_QAPI,
    MODULE_INIT_QOM,
    MODULE_INIT_MAX
} module_init_type;

#define block_init(function) module_init(function, MODULE_INIT_BLOCK)
#define machine_init(function) module_init(function, MODULE_INIT_MACHINE)
#define qapi_init(function) module_init(function, MODULE_INIT_QAPI)
#define type_init(function) module_init(function, MODULE_INIT_QOM)

void register_module_init(void (*fn)(void), module_init_type type);

void module_call_init(module_init_type type);

#endif
```
* accel_list数组
```c

static struct {
    const char *opt_name;
    const char *name;
    int (*available)(void);
    int (*init)(void);
    int *allowed;
} accel_list[] = {
    { "tcg", "tcg", tcg_available, tcg_init, &tcg_allowed },
    { "xen", "Xen", xen_available, xen_init, &xen_allowed },
    { "kvm", "KVM", kvm_available, kvm_init, &kvm_allowed },
    { "qtest", "QTest", qtest_available, qtest_init, &qtest_allowed },
};

```

* 虚拟机的初始化
```c

typedef struct QEMUMachine {
    const char *name;
    const char *alias;
    const char *desc;
    QEMUMachineInitFunc *init; //虚拟机的初始化函数在构建结构体的在这里注册
    QEMUMachineResetFunc *reset;                      |
    int use_scsi;                                     |
    int max_cpus;                                     |
    unsigned int no_serial:1,                         |
        no_parallel:1,                                |  
        use_virtcon:1,                                |
        no_floppy:1,                                  |
        no_cdrom:1,                                   |
        no_sdcard:1;                                  |
    int is_default;                                   |
    const char *default_machine_opts;                 |
    GlobalProperty *compat_props;                     |
    struct QEMUMachine *next;                         |
    const char *hw_version;                           |
} QEMUMachine;                                        |
                                                      |
                                                      |
                                                      |
static QEMUMachine pc_machine_v1_3 = {                |
    .name = "pc-1.3",                                 |
    .alias = "pc",                                    |
    .desc = "Standard PC",                            |
    .init = pc_init_pci, //注册的初始化函数 <---------|
    .max_cpus = 255,
    .is_default = 1,
    .default_machine_opts = KVM_MACHINE_OPTIONS,
};


static void pc_init_pci(ram_addr_t ram_size,
                        const char *boot_device,
                        const char *kernel_filename,
                        const char *kernel_cmdline,
                        const char *initrd_filename,
                        const char *cpu_model)
{
//最重要的初始化函数pc_init1
    pc_init1(get_system_memory(),
             get_system_io(),
             ram_size, boot_device,
             kernel_filename, kernel_cmdline,
             initrd_filename, cpu_model, 1, 1);
}

 configure_accelerator()//解析启动参数，通过ret = accel_list[i].init()调用 kvm_init()函数
         ------kvm_init()// 获取 kvmfd ,vmfd
/*
s->fd = qemu_open("/dev/kvm", O_RDWR);        kvm_init()/line: 1309
ret = kvm_ioctl(s, KVM_GET_API_VERSION, 0);   kmv_init()/line: 1316
s->vmfd = kvm_ioctl(s, KVM_CREATE_VM, 0);     kvm_init()/line: 1339
*/





pc_init1()
    ------>pc_cpus_init()                                               |--选择使用tcg还是kvm
	    |----->pc_new_cpu()--->cpu_x86_init()-->x86_cpu_realize()-->qemu_init_vcpu()--->qemu_kvm_start_vcpu()---->qemu_thread_create()创建一个线程，运行线程函数qemu_kvm_cpu_thread_fn
	    
            qemu_kvm_cpu_thread_fn() //是一个死循环
                  ---->kvm_init_vcpu() //创建三大描述符之一vcpufd (kvmfd, vmfd)
                          ------------>kvm_arch_init_vcpu()//初始化cpu架构相关的数据结构
                    //死循环
                  ---->kvm_cpu_exec() //初始化struct kvm_run，让vm跑起来，从此处进入了kvm的内核处理阶段，并等待返回结果，同时根据返回的原因进行相关的处理eg. KVM_EXIT_IO
                  ----->cpu_handle_guest_debug()//例外处理函数
                  ---->qemu_kvm_wait_io_event() //IO事件处理     
	    //内存虚拟化很难，没看懂
    ------->pc_memory_init()--->memory_region_init_ram()-->qemu_ram_alloc()--->qemu_ram_alloc_from_ptr()
										|----每个块称为RAMBlock，由ram_list链表链接
```
