### 中断虚拟化
##### 中断数据结构初始化的过程
1. 中断虚拟化的关键在于对中断控制器的模拟，x86上中断控制器主要有旧的中断控制器PIC(intel 8259a)和适应于SMP框架的IOAPIC/LAPIC两种。
2. 中断的虚拟化是在kvm实现的，KVM向上层提供接口
3. 中断控制器的创建
```c
QEMU中的步骤
configure_accelerator
    --> ret = accel_list[i].init();
        --> kvm_init
            --> kvm_irqchip_create
                --> kvm_vm_ioctl(s, KVM_CREATE_IRQCHIP) //从这里开始调用KVM的接口
		      ---->kvm_arch_vm_ioctl()//内核函数
                --> kvm_init_irq_routing
```
4. qemu通过kvm的kvm_vm_ioctl()命令KVM_CREATE_IRQCHIP调用到kvm内核模块中，在内核模块中创建和初始化PIC/IOAPIC设备
```c

struct kvm_ioapic {
	u64 base_address;
	u32 ioregsel;
	u32 id;
	u32 irr;
	u32 pad;
	union kvm_ioapic_redirect_entry redirtbl[IOAPIC_NUM_PINS];
	unsigned long irq_states[IOAPIC_NUM_PINS];
	struct kvm_io_device dev;
	struct kvm *kvm;
	spinlock_t lock;
	struct rtc_status rtc_status;
	struct delayed_work eoi_inject;
	u32 irq_eoi[IOAPIC_NUM_PINS];
	u32 irr_delivered;
};

static const struct kvm_io_device_ops ioapic_mmio_ops = {
	.read     = ioapic_mmio_read,
	.write    = ioapic_mmio_write,
};

//在kvm_vm_ioctl()中根据命令KVM_CREATE_IRQCHIP初始化中断
kvm_arch_vm_ioctl()
    ----->kvm_pic_init(kvm) //PIC的初始化
    ----->kvm_ioapic_init(kvm) // IOAPIC的初始化
	      ------>INIT_DELAYED_WORK(&ioapic->eoi_inject, kvm_ioapic_eoi_inject_work);//初始化延迟工作队列(队列里放一个线程)，线程执行函数kvm_ioapic_eoi_inject_work
	      ------>kvm_iodevice_init(&ioapic->dev, &ioapic_mmio_ops);//初始化IOAPIC的读写操作
	      ------>kvm_io_bus_register_dev(kvm, KVM_MMIO_BUS, ioapic->base_address,//把IOAPIC注册到MMIO_BUS总线
				      IOAPIC_MEM_LENGTH, &ioapic->dev);
	
```
5. 中断处理的逻辑放在kvm内核模块中进行实现，但设备的模拟呈现还是需要qemu设备模拟器来搞定
* QEMU通过设置全局变量kvm_kernel_irqchip来表示guest是否创建IRQ
```c
#define kvm_irqchip_in_kernel() (kvm_kernel_irqchip)
```
* QEMU中IOAPIC设备的初始化
```c
pc_init_pci()
    --->pc_init1()
          ------>ioapic_init()
	              -------->qdev_create(NULL, "kvm-ioapic");

```

###### 中断路由表
1. 内核中中断路由相关的数据结构

```c
//中断路由项
struct kvm_irq_routing_entry {
	__u32 gsi;
	__u32 type;
	__u32 flags;
	__u32 pad;
	union {
		struct kvm_irq_routing_irqchip irqchip;
		struct kvm_irq_routing_msi msi;
		struct kvm_irq_routing_s390_adapter adapter;
		struct kvm_irq_routing_hv_sint hv_sint;
		struct kvm_irq_routing_xen_evtchn xen_evtchn;
		__u32 pad[8];
	} u;
};
//中断路由
struct kvm_irq_routing {
	__u32 nr;
	__u32 flags;
	struct kvm_irq_routing_entry entries[];
};

//中断路由表
/*
kvm_irq_routing_table这个数据结构描述了“每个虚拟机的中断路由表”，对应于kvm数据结构的irq_routing成员。
chip是个二维数组表示三个中断控制器芯片的每一个管脚（最多24个pin）的GSI，nr_rt_entries表示中断路由表中
存放的“中断路由项”的数目，最为关键的struct hlist_head map[0]是一个哈希链表结构体数组，数组以GSI作为索引
可以找到同一个irq关联的所有kvm_kernel_irq_routing_entry（中断路由项）。
*/
struct kvm_irq_routing_table {
	int chip[KVM_NR_IRQCHIPS][KVM_IRQCHIP_NUM_PINS];
	u32 nr_rt_entries;
	/*
	 * Array indexed by gsi. Each entry contains list of irq chips
	 * the gsi is connected to.
	 */
	struct hlist_head map[];
}
/*

gsi表示这个中断路由项对应的GSI号，type表示该gsi的类型取值可以是 KVM_IRQ_ROUTING_IRQCHIP, KVM_IRQ_ROUTING_MSI等，
set函数指针很重要表示该gsi关联的中断触发方法（不同type的GSI会调用不同的set触发函数），
hlist_node则是中断路由表哈希链表的节点，通过link将同一个gsi对应的中断路由项链接到map对应的gsi上。

*/
struct kvm_kernel_irq_routing_entry {
	u32 gsi;
	u32 type;
	int (*set)(struct kvm_kernel_irq_routing_entry *e,
		   struct kvm *kvm, int irq_source_id, int level,
		   bool line_status);
	union {
		struct {
			unsigned irqchip;
			unsigned pin;
		} irqchip;
		struct {
			u32 address_lo;
			u32 address_hi;
			u32 data;
			u32 flags;
			u32 devid;
		} msi;
		struct kvm_s390_adapter_int adapter;
		struct kvm_hv_sint hv_sint;
		struct kvm_xen_evtchn xen_evtchn;
	};
	struct hlist_node link;
};

```





















