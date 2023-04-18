### 设备直通
#### IOMMU
1. IOMMU类似于MMU虚拟地址和物理地址的转换。设备必须访问真实的物理地址HPA,而虚机可见的是GPA；二是如果让虚机填入真正的HPA，那样的话相当于虚机可以直接访问物理地址，
会有安全隐患。<mark>当硬件支持IOMMU时, IO设备访问的地址被IOMMU截获，并进行重映射(IO Virtual Addr --> IO Physical Addr)。IOMMU也需要页表映射</mark>
IOMMU可以将连续的虚拟地址映射到不连续的多个物理内存片段，这部分功能于MMU类似，对于没有IOMMU的情况，设备访问的物理空间必须是连续的，IOMMU可有效的解决这个问题。

2. 屏蔽物理地址，起到保护作用。典型应用包括两个：一是实现用户态驱动，由于IOMMU的映射功能，使HPA对用户空间不可见，在vfio部分还会举例。
二是将设备透传给虚机，使HPA对虚机不可见，并将GPA映射为HPA

3. ntel VT-d 虚拟化方案主要目的是解决IO虚拟化中的安全和性能这两个问题，这其中最为核心的技术就是<mark>DMA Remapping和Interrupt Remapping</mark>。 
DMA Remapping通过IOMMU页表方式将直通设备对内存的访问限制到特定的domain中，在提高IO性能的同时完成了直通设备的隔离，保证了直通设备DMA的安全性。
Interrupt Remapping则提供IO设备的中断重映射和路由功能，来达到中断隔离和中断迁移的目的，提升了虚拟化环境下直通设备的中断处理效率

4. Interrupt Remapping的出现改变了x86体系结构上的中断投递方式，中断请求会先被中断重映射硬件截获后再通过查询中断重映射表的方式最终投递到目标CPU上

#### VFIO 设备直通
1. VFIO内核组件主要包括如下图所示，通过设备文件向用户态提供统一访问接口vfio interface层
2. 一个container可以理解为实际的物理资源集合，每个container中可以有多个group，group描述了设备在物理上的划分，
一个group可以有多个device，划分的逻辑取决于硬件上的IOMMU拓扑结构

3. group 是IOMMU能够进行DMA隔离的最小硬件单元，一个group内可能只有一个device，也可能有多个device，这取决于物理平台上硬件的IOMMU拓扑结构。
设备直通的时候一个group里面的设备必须都直通给一个虚拟机。 不能够让一个group里的多个device分别从属于2个不同的VM，也不允许部分device在host上
而另一部分被分配到guest里， 因为就这样一个guest中的device可以利用DMA攻击获取另外一个guest里的数据，就无法做到物理上的DMA隔离。

4. vfio的底层支持是IOMMU，vfio_group于iommu_group对应
5. VFIO(Virtual Function I/O) 是内核提供的一种用户态设备驱动方案。VFIO 驱动可以安全地把设备 I/O，中断，DMA 等能力呈现给用户空间
```c
VFIO container
VFIO group
VFIO device

container
+------------------------+
|    group0    group1    |
|  +-------+  +------+   |
|  | dev0  |  | dev2 |   |
|  | dev1  |  +------+   |
|  +-------+             |
+------------------------+


+-----------------------------------------+
|            vfio interface               |
+-----------------------------------------+
|  vfio_iommu_driver |       vfio_pci     |
+--------------------+--------------------+
|        iommu       |       pci_bus      |
+--------------------+--------------------+


struct vfio_iommu_driver_ops {
	char		*name;
	struct module	*owner;
	void		*(*open)(unsigned long arg);
	void		(*release)(void *iommu_data);
	long		(*ioctl)(void *iommu_data, unsigned int cmd,
				 unsigned long arg);
	int		(*attach_group)(void *iommu_data,
					struct iommu_group *group,
					enum vfio_group_type);
	void		(*detach_group)(void *iommu_data,
					struct iommu_group *group);
	int		(*pin_pages)(void *iommu_data,
				     struct iommu_group *group,
				     dma_addr_t user_iova,
				     int npage, int prot,
				     struct page **pages);
	void		(*unpin_pages)(void *iommu_data,
				       dma_addr_t user_iova, int npage);
	void		(*register_device)(void *iommu_data,
					   struct vfio_device *vdev);
	void		(*unregister_device)(void *iommu_data,
					     struct vfio_device *vdev);
	int		(*dma_rw)(void *iommu_data, dma_addr_t user_iova,
				  void *data, size_t count, bool write);
	struct iommu_domain *(*group_iommu_domain)(void *iommu_data,
						   struct iommu_group *group);
	void		(*notify)(void *iommu_data,
				  enum vfio_iommu_notify_type event);
};

struct vfio_iommu_driver {
	const struct vfio_iommu_driver_ops	*ops;
	struct list_head			vfio_next;
};
/*
Container是管理内存资源，和IOMMU、DMA及地址空间相关，可以通过打开设备文件/dev/vfio/vfio来获取container对应的文件描述符，
在内核vfio/vfio.c中有对应该vfio设备文件的具体操作实现，ioctl主要是可以获取IOMMU相关的信息，vfio会将用户态对IOMMU相关操作发给底层的vfio_iommu驱动进行操作
*/
struct vfio_container {
	struct kref			kref;
	struct list_head		group_list;
	struct rw_semaphore		group_lock;
	struct vfio_iommu_driver	*iommu_driver;
	void				*iommu_data;
	bool				noiommu;
};

struct vfio_group {
	struct device 			dev;
	struct cdev			cdev;
	/*
	 * When drivers is non-zero a driver is attached to the struct device
	 * that provided the iommu_group and thus the iommu_group is a valid
	 * pointer. When drivers is 0 the driver is being detached. Once users
	 * reaches 0 then the iommu_group is invalid.
	 */
	refcount_t			drivers;
	unsigned int			container_users;
	struct iommu_group		*iommu_group;
	struct vfio_container		*container;
	struct list_head		device_list;
	struct mutex			device_lock;
	struct list_head		vfio_next;
	struct list_head		container_next;
	enum vfio_group_type		type;
	struct mutex			group_lock;
	struct kvm			*kvm;
	struct file			*opened_file;
	struct blocking_notifier_head	notifier;
};

struct vfio_device {
	struct device *dev;
	const struct vfio_device_ops *ops;
	/*
	 * mig_ops/log_ops is a static property of the vfio_device which must
	 * be set prior to registering the vfio_device.
	 */
	const struct vfio_migration_ops *mig_ops;
	const struct vfio_log_ops *log_ops;
	struct vfio_group *group;
	struct vfio_device_set *dev_set;
	struct list_head dev_set_list;
	unsigned int migration_flags;
	/* Driver must reference the kvm during open_device or never touch it */
	struct kvm *kvm;

	/* Members below here are private, not for driver use */
	unsigned int index;
	struct device device;	/* device.kref covers object life circle */
	refcount_t refcount;	/* user count on registered device*/
	unsigned int open_count;
	struct completion comp;
	struct list_head group_next;
	struct list_head iommu_entry;
};
```
##### vfio_pci
1. vfio_pci模块封装pci设备驱动并和用户态程序进行配合完成用户态的设备配置模拟、Bar空间重定向及中断重映射等功能


```c

static struct pci_driver vfio_pci_driver = {
	.name			= "vfio-pci",
	.id_table		= vfio_pci_table,
	.probe			= vfio_pci_probe,//初始化和注册vfio_device
	.remove			= vfio_pci_remove,
	.sriov_configure	= vfio_pci_sriov_configure,
	.err_handler		= &vfio_pci_core_err_handlers,
	.driver_managed_dma	= true,
};


static int __init vfio_pci_init(void)
{
.......................
	/* Register and scan for devices */
	ret = pci_register_driver(&vfio_pci_driver);// 注册vfio_pci_driver 
	return 0;
}

static const struct vfio_device_ops vfio_pci_ops = {
	.name		= "vfio-pci",
	.init		= vfio_pci_core_init_dev,
	.release	= vfio_pci_core_release_dev,
	.open_device	= vfio_pci_open_device,
	.close_device	= vfio_pci_core_close_device,
	.ioctl		= vfio_pci_core_ioctl,//最重要的函数
	.device_feature = vfio_pci_core_ioctl_feature,
	.read		= vfio_pci_core_read,
	.write		= vfio_pci_core_write,
	.mmap		= vfio_pci_core_mmap,
	.request	= vfio_pci_core_request,
	.match		= vfio_pci_core_match,
};
/*

要暴露设备的能力到用户态空间，要让用户态能够直接访问设备配置空间并处理设备中断，对于PCI设备而言，
其配置其配置空间是一个VFIO region，对应着一块MMIO内存，通过建立dma重映射让用户态能够直接访问设备配置空间，
另外还需要建立中断重映射以让用户态驱动处理设备中断事件。
*/
long vfio_pci_core_ioctl(struct vfio_device *core_vdev, unsigned int cmd,
			 unsigned long arg)
{
	struct vfio_pci_core_device *vdev =
		container_of(core_vdev, struct vfio_pci_core_device, vdev);
	void __user *uarg = (void __user *)arg;

	switch (cmd) {
	case VFIO_DEVICE_GET_INFO:
		return vfio_pci_ioctl_get_info(vdev, uarg);
	case VFIO_DEVICE_GET_IRQ_INFO:
		return vfio_pci_ioctl_get_irq_info(vdev, uarg);
	case VFIO_DEVICE_GET_PCI_HOT_RESET_INFO:
		return vfio_pci_ioctl_get_pci_hot_reset_info(vdev, uarg);
	case VFIO_DEVICE_GET_REGION_INFO: //获取vfio_region的信息，包括配置空间的region和bar空间的region等
		return vfio_pci_ioctl_get_region_info(vdev, uarg);
	case VFIO_DEVICE_IOEVENTFD:
		return vfio_pci_ioctl_ioeventfd(vdev, uarg);
	case VFIO_DEVICE_PCI_HOT_RESET:
		return vfio_pci_ioctl_pci_hot_reset(vdev, uarg);
	case VFIO_DEVICE_RESET:
		return vfio_pci_ioctl_reset(vdev, uarg);
	case VFIO_DEVICE_SET_IRQS: //完成中断相关的设置
		return vfio_pci_ioctl_set_irqs(vdev, uarg);
	default:
		return -ENOTTY;
	}
}

vfio_pci_probe()
     ------->vdev = vfio_alloc_device(vfio_pci_core_device, vdev, &pdev->dev, &vfio_pci_ops);//vfio_pci_ops是vfio的操作函数，在这里注册
     //最后调用_vfio_alloc_device函数，初始化vfio_device,然后包装成结构体vfio_pci_core_device
     //然后初始化vfio_device_opes
              -------->_vfio_alloc_device()
				------->vfio_init_device()//初始化vfio_device结构体
     ------->vfio_pci_core_register_device(vdev);
	      --------->vfio_register_group_dev()//通过该函数把group中的vfio_device全部注册到device链表中
	                   ---->__vfio_register_dev()
			          --->device_add()
			   ----->vfio_group_find_or_alloc() //绑定group和Container,之后细说
```


##### Container,group和device绑定
1. VFIO的Container和IOMMU之间的绑定,通过在用户态通过ioctl调用VFIO_SET_IOMMU完成,绑定意味着将container管理的所有group都attach到IOMMU中,
最终会将每个group中的每个设备都attach到IOMMU中,这意味着为设备建立IO页表完成初始化
2. vfio是一个独立的内核模块

```c

static const struct file_operations vfio_fops = {
	.owner		= THIS_MODULE,
	.open		= vfio_fops_open,
	.release	= vfio_fops_release,
	.unlocked_ioctl	= vfio_fops_unl_ioctl, //iommu和Container的绑定是在这里注册的
	.compat_ioctl	= compat_ptr_ioctl,|
};                                         |
                                           |
static struct miscdevice vfio_dev = {      |
	.minor = VFIO_MINOR,               |
	.name = "vfio",                    |
	.fops = &vfio_fops, <-------------|
	.nodename = "vfio/vfio",          |
	.mode = S_IRUGO | S_IWUGO,        |
};                                        |
					  |
vfio_init()				  |
   ---->vfio_container_init();            |
        ------>ret = misc_register(&vfio_dev);

//通过VFIO_SET_IOMMU来完成
vfio_fops_unl_ioctl()
    --->vfio_ioctl_set_iommu()
         --->__vfio_container_attach_groups(container, driver, data)
	           //遍历group的list，然后调用struct vfio_iommu_driver_ops vfio_iommu_driver_ops_type1注册的函数vfio_iommu_type1_attach_group()绑定
	         ------->ret = driver->ops->attach_group()
		        ---->vfio_iommu_type1_attach_group()///复杂，以后在补充具体的vfio和IOMMU的底层绑定机制
		               --->iommu_attach_group()
			              --->__iommu_attach_group()        //调用函数iommu_group_do_attach_device()函数绑定group中的device
				          --->__iommu_group_for_each_dev(group, domain,iommu_group_do_attach_device);

iommu_group_do_attach_device()
    -->__iommu_attach_device() //调用注册的struct iommu_ops viommu_ops中的函数viommu_attach_dev()去绑定vfio的device
       ---->ret = domain->ops->attach_dev(domain, dev);
                               -------->viommu_attach_dev()//建立设备的IO页表
```

2. Container和group之间的绑定由VFIO_GROUP_SET_CONTAINER设置,vfio提供接口vfio_group_ioctl_set_container()
，可由用户态指定把group绑定到哪一个Containter中

```c

static const struct file_operations vfio_group_fops = {
	.owner		= THIS_MODULE,
	.unlocked_ioctl	= vfio_group_fops_unl_ioctl,
	.compat_ioctl	= compat_ptr_ioctl,
	.open		= vfio_group_fops_open,
	.release	= vfio_group_fops_release,
};
vfio_register_group_dev(
   --->vfio_group_find_or_alloc(
        --->vfio_create_group()
           --->vfio_group_alloc()//在这里注册vfio_group_fops 

vfio_group_fops_unl_ioctl() //根据VFIO_GROUP_SET_CONTAINER设置,
 ---->vfio_group_ioctl_set_container()//找到一个合适的Container
       --->vfio_container_attach_group()
              ------->ret = driver->ops->attach_group()
		        ---->vfio_iommu_type1_attach_group()//不确定是否走到这里
```

3. Device和Group之间的绑定关系源自设备和IOMMU的物理拓扑结构,由device注册时决定



### QEMU直通设备PCI配置空间模拟(QEMU的设置)
1. 对于设备的MMIO空间访问,则可以通过建立EPT页表将设备的MMIO物理内存映射到虚拟的MMIO地址空间,让虚拟机能够直接通过MMIO访问PCI设备的bar空间,提高IO性能.
2. QEMU中的QOM类型模块的注册接口函数为type_init(), type_init通过宏展开最终将展开成do_qemu_init_XXXX_register_types这个在main函数执行前调用的函数。
它再通过register_module_init将XXXX_register_types插入init_type_list[MODULE_INIT_QOM]链表中。完成模块注册。
qemu主初始化函数qemu_init中就可以在根据需要调用module_call_init(type)执行对应类型模块的初始化了：![参考](https://66ring.github.io/2021/04/12/universe/qemu/qemu_initial_framework/)

3. <mark>vfio_pci的初始化函数vfio_initfn()</mark>
```c
//QEMU中vfio PCI类型的设备在这里进行注册,就是定义一个TypeInfo类型的vfio_pci ,挂载初始化函数vfio_initfn,使用type_init函数将其放到init_type_list链表中
static void vfio_pci_dev_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *pdc = PCI_DEVICE_CLASS(klass);

    dc->reset = vfio_pci_reset;
    dc->props = vfio_pci_dev_properties;
    pdc->init = vfio_initfn; 
    pdc->exit = vfio_exitfn;
    pdc->config_read = vfio_pci_read_config;
    pdc->config_write = vfio_pci_write_config;
}

static const TypeInfo vfio_pci_dev_info = {
    .name = "vfio-pci",
    .parent = TYPE_PCI_DEVICE,
    .instance_size = sizeof(VFIODevice),
    .class_init = vfio_pci_dev_class_init,
};

static void register_vfio_pci_dev_type(void)
{
    type_register_static(&vfio_pci_dev_info);
}

type_init(register_vfio_pci_dev_type)
```

4. Qemu为每个PCI直通设备都建立一个虚拟数据结构 VFIODevice，保存物理PCI设备的相关信息，由vfio_get_device来获取
5. PCIe bar,Type 0报头有6个bar可用(每个bar的大小为32位)，而Type 1头只有2个bar可用。Type 1报头在所有网桥设备中都可以找到 [参考](https://blog.csdn.net/u013253075/article/details/119361574)
![](https://drive.google.com/uc?export=view&id=1J_KjAAOSTKjMoXuKfGp1vpd4Wunu451O) 

```c

typedef struct VFIODevice {
    PCIDevice pdev;
    int fd;
    VFIOINTx intx;
    unsigned int config_size;
    off_t config_offset; /* Offset of config space region within device fd */
    unsigned int rom_size;
    off_t rom_offset; /* Offset of ROM region within device fd */
    int msi_cap_size;
    VFIOMSIVector *msi_vectors;
    VFIOMSIXInfo *msix;
    int nr_vectors; /* Number of MSI/MSIX vectors currently in use */
    int interrupt; /* Current interrupt type */
    VFIOBAR bars[PCI_NUM_REGIONS - 1]; /* No ROM */
    PCIHostDeviceAddress host;
    QLIST_ENTRY(VFIODevice) next;
    struct VFIOGroup *group;
    bool reset_works;
} VFIODevice;

typedef struct VFIOGroup {
    int fd;
    int groupid;
    VFIOContainer *container;
    QLIST_HEAD(, VFIODevice) device_list;
    QLIST_ENTRY(VFIOGroup) next;
    QLIST_ENTRY(VFIOGroup) container_next;
} VFIOGroup;

enum {
	VFIO_PCI_BAR0_REGION_INDEX,
	VFIO_PCI_BAR1_REGION_INDEX,
	VFIO_PCI_BAR2_REGION_INDEX,
	VFIO_PCI_BAR3_REGION_INDEX,
	VFIO_PCI_BAR4_REGION_INDEX,
	VFIO_PCI_BAR5_REGION_INDEX,
	VFIO_PCI_ROM_REGION_INDEX,
	VFIO_PCI_CONFIG_REGION_INDEX,
	VFIO_PCI_NUM_REGIONS
};

static const MemoryRegionOps vfio_bar_ops = {
    .read = vfio_bar_read,
    .write = vfio_bar_write,
    .endianness = DEVICE_LITTLE_ENDIAN,
};

vfio_initfn()  //通过vfio_get_device/group获取到直通设备的基本信息之后，会调用pread设备的fd获取到设备的配置空间信息的一份拷贝，qemu会写入一些自定义的config配置。
    --->vfio_get_group()//打开文件,绑定Container
          ---->qemu_opne("/dev/vfio/groupid")
          ---->vfio_connect_container()
	        ------->ioctl(group->fd, VFIO_GROUP_SET_CONTAINER, &container->fd)) //绑定Container
	        ------->ret = ioctl(fd, VFIO_SET_IOMMU, VFIO_TYPE1_IOMMU); //设置IOMMU
    ---->vfio_get_device() //QEMU通过ioctl()函数调用kvm接口获取到PCI设备的Bar空间信息
         ----->ret = ioctl(vdev->fd, VFIO_DEVICE_GET_REGION_INFO, &reg_info);
    ----> vfio_load_rom()
           ----->memory_region_init_ram()//从QEMU中分配一个区域作为PCI的映射空间
	   ----->pci_register_bar() //注册PCI bar到PCIIORegion,就是PCI bar地址空间的一些设置(PCI手册?)
    ---->vfio_map_bars() //直通PCI设备的MMIO内存主要是指其Bar空间
        ---->vfio_map_bar()
	        ------->memory_region_init_io()//通过该函数将qemu内存虚拟化的MemoryRegion设置为IO类型的region,
		                               //qemu会为该IO类型的MemoryRegion设置ops为vfio_bar_ops，这样后续对于该块内存的读写会经过qemu VFIO模块注册的接口来进行。
	//PCI设备的MMIO内存信息，但是还没有真正的将物理内存中的Bar空间映射到qemu
	        -------->vfio_mmap_bar()
		           ---->mmap()//将bar空间设置的物理内存映射到qemu中


       --------------------内核-------------------
/*
映射mmap接口对应的是VFIO设备在内核中注册的vfio_pci_core_mmap 函数，在内核中，该函数会为vma注册一个mmap的ops，对应着注册了一个缺页处理函数，
当用户态程序访问该段虚拟内存缺页时，调用注册的缺页处理函数，完成虚拟地址到实际物理地址的映射
*/


static const struct vm_operations_struct vfio_pci_mmap_ops = {
	.open = vfio_pci_mmap_open,
	.close = vfio_pci_mmap_close,
	.fault = vfio_pci_mmap_fault,
};
/*
对于MMIO内存的的映射，主要是将物理内存中的MMIO空间映射到了qemu的虚拟地址空间，
然后再由qemu将该段内存注册进虚拟机作为虚拟机的一段物理内存，在这个过程中会建立从gpa到hpa的EPT页表映射，提升MMIO的性能。
*/
```

### DMA重映射
1. 直通设备只能访问iova,从iova到实际物理地址的映射是在IOMMU中完成的,之后才能设备通过DMA可以直接使用iova地址访问物理内存,
一般在dma_allooc分配设备能够访问的内存的时候，会分配iova地址和实际的物理地址空间，并在iommu中建立映射关系。

2. VFIO设备的初始化开始，在获取设备信息之前会先获取到设备所属的group和Container，并调用VFIO_SET_IOMMU完成container和IOMMU的绑定，并attach由VFIO管理的所有设备。
在VFIO_SET_IOMMU之后，注册该地址空间，其region_add函数为 vfio_listener_region_add，意思是当内存空间布局发生变化这里是增加内存的时候都会调用该接口。

```c
+--------+  iova  +--------+  gpa  +----+
| device |   ->   | memory |   <-  | vm |
+--------+        +--------+       +----+



static MemoryListener vfio_memory_listener = {
    .begin = vfio_listener_dummy1,
    .commit = vfio_listener_dummy1,
    .region_add = vfio_listener_region_add,
    .region_del = vfio_listener_region_del,
    .region_nop = vfio_listener_dummy2,
    .log_start = vfio_listener_dummy2,
    .log_stop = vfio_listener_dummy2,
    .log_sync = vfio_listener_dummy2,
    .log_global_start = vfio_listener_dummy1,
    .log_global_stop = vfio_listener_dummy1,
    .eventfd_add = vfio_listener_dummy3,
    .eventfd_del = vfio_listener_dummy3,
};

static int vfio_connect_container(VFIOGroup *group)
{
	 QLIST_FOREACH(container, &container_list, next) {
        if (!ioctl(group->fd, VFIO_GROUP_SET_CONTAINER, &container->fd)) {
            group->container = container; //设置Container
            QLIST_INSERT_HEAD(&container->group_list, group, container_next);
            return 0;
        }
    }

    fd = qemu_open("/dev/vfio/vfio", O_RDWR);

    ret = ioctl(fd, VFIO_SET_IOMMU, VFIO_TYPE1_IOMMU); //设置IOMMU
   .............      
   container->iommu_data.listener = vfio_memory_listener;
   container->iommu_data.release = vfio_listener_release;

  memory_listener_register(&container->iommu_data.listener,
                                 get_system_memory());
}
```
3. 当为设备进行DMA分配一块内存时，实际是以MemoryRegion的形式存在的，也就是说虚拟机进行dma alloc 会调用region_add函数，进而调用注册的vfio_listener_region_add()函数，
MemoryRegion意味着分配了一块物理内存，还需要IOVA和映射关系才行。这里，IOVA地址使用的是section->offset_within_address_space，为什么可以这样，
因为IOVA地址只是作为设备识别的地址，只要建立了映射关系就有意义。

4. 建立映射的关键在于vfio_dma_map，通过ioctl调用container->fd接口VFIO_IOMMU_MAP_DMA完成DMA重映射。为什么是container->fd，因为VFIO Container管理内存资源，
与IOMMU直接绑定，而IOMMU是完成IOVA到实际物理内存映射的关键。qemu只知道这一段内存的虚拟地址vaddr，所以将vaddr,iova和size传给内核，由内核获取物理内存信息完成映射。
```c
vfio_connect_container() 
   ---->container->iommu_data.listener = vfio_memory_listener;//注册一个listener
   ---->memory_listener_register()
         ---->listener_add_address_space()
	        ---->listener->region_add(listener, &section);//调用vfio_memory_listener.region_add(),也就是vfio_listener_region_add()
                               ------->vfio_listener_region_add()
					---->vfio_dma_map(container, iova, end - iova, vaddr, section->readonly);//建立iova到物理内存的映射
//该函数需要调用内核的接口才能完成iova到物理地址的映射
static int vfio_dma_map(VFIOContainer *container, target_phys_addr_t iova,
                        ram_addr_t size, void *vaddr, bool readonly)
{
    struct vfio_iommu_type1_dma_map map = {
        .argsz = sizeof(map),
        .flags = VFIO_DMA_MAP_FLAG_READ,
        .vaddr = (__u64)(intptr_t)vaddr,
        .iova = iova,
        .size = size,
    };

    if (!readonly) {
        map.flags |= VFIO_DMA_MAP_FLAG_WRITE;
    }
      //KVM接口
    if (ioctl(container->fd, VFIO_IOMMU_MAP_DMA, &map)) {
        DPRINTF("VFIO_MAP_DMA: %d\n", -errno);
        return -errno;
    }

    return 0;
}
```
##### 内核中的设置IOMMU derive

```c
//在内核中IOMMU derive 作为一个独立的module注册到内核的
static const struct vfio_iommu_driver_ops vfio_iommu_driver_ops_type1 = {
	.name			= "vfio-iommu-type1",
	.owner			= THIS_MODULE,
	.open			= vfio_iommu_type1_open,
	.release		= vfio_iommu_type1_release,
	.ioctl			= vfio_iommu_type1_ioctl, /// iommu命令的处理函数
	.attach_group		= vfio_iommu_type1_attach_group,
	.detach_group		= vfio_iommu_type1_detach_group,
	.pin_pages		= vfio_iommu_type1_pin_pages,
	.unpin_pages		= vfio_iommu_type1_unpin_pages,
	.register_device	= vfio_iommu_type1_register_device,
	.unregister_device	= vfio_iommu_type1_unregister_device,
	.dma_rw			= vfio_iommu_type1_dma_rw,
	.group_iommu_domain	= vfio_iommu_type1_group_iommu_domain,
	.notify			= vfio_iommu_type1_notify,
};

static int __init vfio_iommu_type1_init(void)
{
	return vfio_register_iommu_driver(&vfio_iommu_driver_ops_type1);
}


vfio_iommu_type1_ioctl()
  --->vfio_iommu_type1_map_dma()
        ---->vfio_dma_do_map() 
	      ------>vfio_find_dma()//将用户数据映射到DMA空间,就是分配iova
	      ------>vfio_link_dma() //将iova空间插入到红黑树
/*内核完成建立iova到物理内存的映射之前会将分配的DMA内存给pin住，使用vfio_pin_pages_remote接口可以获取到虚拟地址对应的物理地址和pin住的页数量，
然后vfio_iommu_map进而调用iommu以及smmu的map函数，最终用iova，物理地址信息pfn以及要映射的页数量在设备IO页表中建立映射关系
*/
	      ------>vfio_pin_map_dma()
	               ----->vfio_pin_pages_remote()
		       ----->vfio_iommu_map()
		                --->iommu_map() 
				     ----_iommu_map()
				         --->__iommu_map()
					      --->__iommu_map_pages()//最后调用iommu_domain_ops 注册的map函数完成iova到物理地址的映射过程
```



### 中断重映射(QEMU handle)
1. 对于PCIe直通设备中断的虚拟化，主要包括三种类型INTx,Msi和Msi-X。传统的INTx中断多在PCI设备上使用,Msi中断的中断号必须连续,Msi-x是Msi的扩展,
Msi-x中断的中断号可以不连续,当Msi/Msi-x打开时INTx中断自动关闭,Msi/Msi-x中断可以同时打开,取决于硬件的设计支持

2. INTx中断的初始化
```c
/*
对于INTx类型的中断，在初始化的时候就进行使能了，qemu通过VFIO device的接口将中断irq set设置到内核中，
并且会注册一个eventfd，设置了eventfd的handler，当发生intx类型的中断时，内核会通过eventfd通知qemu进行处理，qemu会通知虚拟机进行处理。
*/
vfio_initfn()
  --->vfio_enable_intx()
       --->event_notifier_init(&vdev->intx.interrupt, 0);//初始化一个eventfd
       --->qemu_set_fd_handler(irq_set_fd.fd, vfio_intx_interrupt, NULL, vdev);//vfio_intx_interrupt是一个函数指针
             ---->qemu_set_fd_handler2()//初始化IOHandlerRecord *ioh, 并插入到全局的io_handlers中
	            ----->qemu_notify_event();

	//其中vfio_intx_interrupt()
vfio_intx_interrupt()
    --->qemu_set_irq()
         --->irq->handler(irq->opaque, irq->n, level);//调用irq初始化时注册的中断处理函数
//中断处理函数在kvm_ioapic_init()初始化时注册的kvm_ioapic_set_irq()
     kvm_ioapic_set_irq()
         -->kvm_set_irq()
	      --->kvm_vm_ioctl()//调用kvm的接口设置
	            --->ioctl() //ioctl is a sytem call , system call's handler is kvm_vm_ioctl() in kernel  --->virtuial_interrupt.md 中断注入
```

3. Msi-x中断的初始化
* 当虚拟机因为写PCI配置空间而发生VM-exit时，最终会完成msi和msix的使能，以MSIX的使能为例，在qemu侧会设置eventfd的处理函数，并通过kvm将irqfd注册到内核中，进而注册虚拟中断给虚拟机
```c

vfio_pci_dev_class_init() //QEMU的PCI类设备初始化的时候注册vfio_pci_write_config()和vfio_initfn()
-->vfio_pci_write_config()
     ---->msix_enabled()
-->vfio_intifn()
  --->vfio_add_capabilities()
        --->vfio_add_std_cap()
	     --->vfio_setup_msi()
	     --->vfio_setup_msix()
	          ---->msix_init()
		  ---->ret = msix_set_vector_notifiers(&vdev->pdev, vfio_msix_vector_use,
                                    vfio_msix_vector_release); //注册中断向量,vfio_msix_vector_use函数指针

vfio_msix_vector_use()
   --->vector->virq = kvm_irqchip_add_msi_route(kvm_state, msg)
              ---->kvm_irqchip_get_virq()
	            --->kvm_flush_dynamic_msi_routes()
		         --->kvm_irqchip_release_virq()
			       ---->kvm_irqchip_commit_routes()
			             --->ret = kvm_vm_ioctl(s, KVM_SET_GSI_ROUTING, s->irq_routes)
				                --->ioctl()---> //ioctl is a sytem call , system call's handler is kvm_vm_ioctl() in kernel  --->virtuial_interrupt.md 中断注入
   --->qemu_set_fd_handler(event_notifier_get_fd(&vector->interrupt),
                            vfio_msi_interrupt, NULL, vector);
    vfio_msi_interrupt()//中断处理函数
        --->msix_notify()
	      ---stl_le_phys()//把eventfd的数据写入到相应的内存位置.
	--->msi_notify()
    
```














