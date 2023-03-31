###  virtio I/O  虚拟化
1. Linux设备模型是由总线(bus_type)，设备(device)，驱动(device_driver)这三大数据结构来描述
2. 所有的设备都通过总线来连接。即使有些设备没有连接到一根物理上的总线，Linux也为其设置了一个内部的，虚拟的platform总线
3. Virtio设备为适配Linux Kernel，virtio使用了virtio pcibus类型的虚拟总线。
4. virtio的数据流向图
![virtio的结构图](https://drive.google.com/uc?export=view&id=15tnuU7Xno-en1Mu6ThLY6vXo76JfdyPd)

5. virtio的主要数据结构
![](https://drive.google.com/uc?export=view&id=18vGo611h6cL8-bWJhLoJhvDgEqJrQu63)


#### 总线
```c
static struct bus_type virtio_bus = {
	.name  = "virtio",
	.match = virtio_dev_match,
	.dev_groups = virtio_dev_groups,
	.uevent = virtio_uevent,
	.probe = virtio_dev_probe,//分配virtio_device和virtio_driver
	.remove = virtio_dev_remove,
};


static int virtio_init(void)
{
	if (bus_register(&virtio_bus) != 0)
		panic("virtio bus registration failed");
	return 0;
}

```

#### 驱动

```c
//注册了一个struct virtio_device，并挂载到了virtio bus类型总线上，并由virtio driver来驱动。>
static struct pci_driver virtio_pci_driver = {
	.name		= "virtio-pci",
	.id_table	= virtio_pci_id_table,
	.probe		= virtio_pci_probe, //设置virtio_pci_config_ops, 并注册virtio_device
	.remove		= virtio_pci_remove,
#ifdef CONFIG_PM_SLEEP
	.driver.pm	= &virtio_pci_pm_ops,
#endif
	.sriov_configure = virtio_pci_sriov_configure,
};

virtio_pci_probe()
    --->virtio_pci_modern_probe()//注册virtio_pci_device的hook函数,包括setup_vq
              --->setup_vq()
	           ------->vring_create_virtqueue() //创建和初始化vring_virtqueue数据结构
		   ------->vp_active_vq()

```

##### virtio netdev
1. Qemu会根据注册的virtio_net_info进行virtio net设备的初始化，并在Qemu自身模拟的pci bus层加入了virtio net设备的初始化信息。
2. 对PCI设备进行枚举和资源分配中介绍了,关联到总线链表中。函数pci_register_driver(&virtio_pci_driver)
就是对链表的每一个Pci设备进行探测，遍历注册的驱动是否支持该设备，如果支持，调用驱动probe函数，完成启用该Pci设备
3. virtio相关的数据结构
![](https://drive.google.com/uc?export=view&id=1R_zlop3NNzv1ji9RKdAhd4pa0p5b2SWI)

```c

static struct virtio_driver virtio_net_driver = {
	.feature_table = features,
	.feature_table_size = ARRAY_SIZE(features),
	.feature_table_legacy = features_legacy,
	.feature_table_size_legacy = ARRAY_SIZE(features_legacy),
	.driver.name =	KBUILD_MODNAME,
	.driver.owner =	THIS_MODULE,
	.id_table =	id_table,
	.validate =	virtnet_validate,
	.probe =	virtnet_probe,
	.remove =	virtnet_remove,
	.config_changed = virtnet_config_changed,
#ifdef CONFIG_PM_SLEEP
	.freeze =	virtnet_freeze,
	.restore =	virtnet_restore,
#endif
};


static int virtnet_probe(struct virtio_device *vdev)
{
    struct net_device *dev; 
    struct virtnet_info *vi;
    dev->netdev_ops = &virtnet_netdev;    <------------netdev操作函数的注册
    SET_ETHTOOL_OPS(dev, &virtnet_ethtool_ops);
    SET_NETDEV_DEV(dev, &vdev->dev);

    vi = netdev_priv(dev);  //通过这里获取virtnet_info数据结构
     vi->dev = dev;
     vi->vdev = vdev;
     vdev->priv = vi;

     /* Use single tx/rx queue pair as default */
     vi->curr_queue_pairs = 1;
     vi->max_queue_pairs = max_queue_pairs;

    /* Allocate/initialize the rx/tx queues, and invoke find_vqs */
     err = init_vqs(vi);       <----------初始化virt queue

     /*register_netdev的出现，表明向Kernel注册了网络设备类型，对于kernel来讲就可以按照普通网卡来管理*/
    err = register_netdev(dev);  

    /* Last of all, set up some receive buffers. */
    vi->nb.notifier_call = &virtnet_cpu_callback;
     err = register_hotcpu_notifier(&vi->nb);
}

init_vqs(vi);          //创建和初始化发送/接收队列
    --->virtnet_alloc_queues()
    --->virtnet_find_vqs()

virtio netdev操作函数集的定义
static const struct net_device_ops virtnet_netdev = {
	.ndo_open            = virtnet_open,
	.ndo_stop   	     = virtnet_close,
	.ndo_start_xmit      = start_xmit, // -------------------------------->发包管理函数
	.ndo_validate_addr   = eth_validate_addr,
	.ndo_set_mac_address = virtnet_set_mac_address,
	.ndo_set_rx_mode     = virtnet_set_rx_mode,
	.ndo_get_stats64     = virtnet_stats,
	.ndo_vlan_rx_add_vid = virtnet_vlan_rx_add_vid,
	.ndo_vlan_rx_kill_vid = virtnet_vlan_rx_kill_vid,
	.ndo_bpf		= virtnet_xdp,
	.ndo_xdp_xmit		= virtnet_xdp_xmit,
	.ndo_features_check	= passthru_features_check,
	.ndo_get_phys_port_name	= virtnet_get_phys_port_name,
	.ndo_set_features	= virtnet_set_features,
	.ndo_tx_timeout		= virtnet_tx_timeout,
};

virtnet_alloc_queues() {
.............

        //初始化接受和发送队列
	vi->sq = kcalloc(vi->max_queue_pairs, sizeof(*vi->sq), GFP_KERNEL);
	if (!vi->sq)
		goto err_sq;
	vi->rq = kcalloc(vi->max_queue_pairs, sizeof(*vi->rq), GFP_KERNEL);
	if (!vi->rq)
		goto err_rq;
..................
}

```
4. 可以把virtqueue理解为一个接口类，而vring_virtqueue作为这个接口的一个实现，vring_virtqueue通过成员vq可以与上述其它struct建立联系。
virtio的环形缓冲区机制是由vring来承载的，vring由三部分组成：Descriptor表(vring_desc)，Available ring(vring_avail)和Used ring(vring_used)。
![](https://drive.google.com/uc?export=view&id=1TUFSP-Hp5mL70jcvQBHqsOhDQ9STl2zl)

#####  scatterlist
1. scatter-gather list分散聚集列表,是内存地址空间中的一种数据结构，其用于描述数据缓冲区
```c

struct send_queue {
	/* Virtqueue associated with this send _queue */
	struct virtqueue *vq;

	/* TX: fragments + linear part + virtio header */
	struct scatterlist sg[MAX_SKB_FRAGS + 2]; //发送队列中使用分散聚集列表

	/* Name of the send queue: output.$index */
	char name[40];

	struct virtnet_sq_stats stats;

	struct napi_struct napi;

	/* Record whether sq is in reset state. */
	bool reset;
};

struct scatterlist {
	unsigned long	page_link;
	unsigned int	offset;
	unsigned int	length;
	dma_addr_t	dma_address;
#ifdef CONFIG_NEED_SG_DMA_LENGTH
	unsigned int	dma_length;
#endif
#ifdef CONFIG_PCI_P2PDMA
	unsigned int    dma_flags;
#endif
};

```


#### 发送数据流分析
1. 当Kernel中的网络数据包从内核协议栈下来后，必然要走到virtnet_netdev中注册的发送函数start_xmit()
2. 从整个前端发送流程可以看出，一个数据包发送时只是将skb的地址及长度等信息通告了virtio driver，而vring的空间是和后端共享的，所以该传输过程为零拷贝，这也是virtio高性能的一个原因。
```c
static netdev_tx_t start_xmit(struct sk_buff *skb, struct net_device *dev)
{
    ......
    err = xmit_skb(sq, skb);  //把sk_buff放入到发送队列中
    ......
    virtqueue_notify(sq->vq); //待发送的信息入队列后，使用virtqueue_kick(sq->vq)通告Host端
    ......
}

struct virtio_net_hdr {
	/* See VIRTIO_NET_HDR_F_* */
	__u8 flags;
	/* See VIRTIO_NET_HDR_GSO_* */
	__u8 gso_type;
	__virtio16 hdr_len;		/* Ethernet + IP + tcp/udp hdrs */
	__virtio16 gso_size;		/* Bytes to append to hdr_len per frame */
	__virtio16 csum_start;	/* Position to start checksumming from */
	__virtio16 csum_offset;	/* Offset after that to place checksum */
};

xmit_skb()
    --->skb_vnet_hdr() // 设置一个virtio_net_hdr的数据结构，用以支持checksum offload与TCP/UDP Segmentation offload。
    --->sg_init_table() //初始化scatterlist
    ---->sg_set_buf() ///主要的操作就是计算待发送数据buffer占用的page的基址，相对基址的偏移量及length,以及页对齐操作
           ------->sg_set_page()
	             ------------>sg_assign_page()
   ----->virtqueue_add_outbuf()
        ---------->virtqueue_add()//开始复制数据,更新avail描述队列


setup_vq()----->vring_create_virtqueue()中作为函数指针传递进取的
virtqueue_notify()
      ---->vp_notify() //调用在vring_virtqueue 建时初始化的函数指针
bool vp_notify(struct virtqueue *vq)
{
	/* we write the queue's selector into the notification register to
	 * signal the other end */
	iowrite16(vq->index, (void __iomem *)vq->priv);
	return true;
}
```


#### Vhost
1. VHOST通过driver的形式在Host Kernel中直接实现了virtio设备的模拟。通过在Host Kernel中对virtios设备的模拟运行
允许Guest与Host Kernel直接进行数据交换，从而避免了用户空间的system call与数据拷贝的性能消耗。
2. Vhost的架构
![](https://drive.google.com/uc?export=view&id=1ISTipqmRcA4lUBboOpTpuDUoz520Q5GL)

3. guest_notifier的使用
* vhost在处理完请求（收到数据包)，将buffer放到used ring上面之后，往call fd里面写入;
* 如果成功设置了irqfd，则kvm会直接中断guest。如果没有成功设置，则走以下的路径：
* Qemu通过select调用监听到该事件(因为vhost的callfd就是qemu里面对应vq的guest_notifier，它已经被加入到selectablefd列表)；
* 调用virtio_pci_guest_notifier_read通知guest；
* guest从used ring上获取相关的数据；

4. host_notifier的使用
* Guest中的virtio设备将数据放入avail ring上面后，写发送命令至virtio pci配置空间；
* Qemu截获寄存器的访问，调用注册的kvm_memory_listener中的eventfd_add回调函数kvm_eventfd_add()；
* 通过kvm_vm_ioctl(kvm_state, KVM_IOEVENTFD, &kick)进入kvm中；
* kvm唤醒挂载在ioeventfd上vhost worker thread；
* vhost worker thread从avail ring上获取相关数据。


5. qemu端的设置
* vhost_net的启用是在中指定vhost=on选项，其初始化流程如下:
* tap设备的创建会调用到net_init_tap()函数；
* net_init_tap()其中会检查选项是否指定vhost=on，如果指定，则会调用到vhost_net_init()进行初始化；
* 通过open(“/dev/vhost-net”, O_RDWR)打开了vhost driver；并通过ioctl(vhost_fd)进行了一系列的初始化

6. Vhost在内核中的初始化
```c

static const struct file_operations vhost_net_fops = {
	.owner          = THIS_MODULE,
	.release        = vhost_net_release,
	.read_iter      = vhost_net_chr_read_iter,
	.write_iter     = vhost_net_chr_write_iter,
	.poll           = vhost_net_chr_poll,
	.unlocked_ioctl = vhost_net_ioctl,
	.compat_ioctl   = compat_ptr_ioctl,
	.open           = vhost_net_open, 	
	.llseek		= noop_llseek,
};

vhost_net_open() {
	struct vhost_net *n;
	struct vhost_dev *dev;
	struct vhost_virtqueue **vqs;
	//在该函数中对vhost相关的数据结构进行相关的初始化
	vhost_dev_init(dev, vqs, VHOST_NET_VQ_MAX,
		       UIO_MAXIOV + VHOST_NET_BATCH,
		       VHOST_NET_PKT_WEIGHT, VHOST_NET_WEIGHT, true,
		       NULL);
/*

vhost_poll_init()创建了一个名为“vhost-$pid”内核线程,$pid为Qemu的PID。
这个内核线程被称为“vhost worker thread”，该worker thread的任务即为处理virtio的I/O事件。
 vhost_work_init()指定线程函数为handle_tx_net
 在handle_tx_net函数中使用socket实现workqueue,

*/        
	vhost_poll_init(n->poll + VHOST_NET_VQ_TX, handle_tx_net, EPOLLOUT, dev);
	vhost_poll_init(n->poll + VHOST_NET_VQ_RX, handle_rx_net, EPOLLIN, dev);

 
}

static struct miscdevice vhost_net_misc = {
	.minor = VHOST_NET_MINOR,
	.name = "vhost-net",
	.fops = &vhost_net_fops,
};

static int __init vhost_net_init(void)
{
	if (experimental_zcopytx)
		vhost_net_enable_zcopy(VHOST_NET_VQ_TX);
	return misc_register(&vhost_net_misc);
}
module_init(vhost_net_init);
```
7. virtio_dev_probe进行virtio设备的初始化,最后Qemu最终调用到vhost_net_start()将vq的配置下发到vhost中
设置vhost_virtqueue中ring相关的成员(desc,avail, used_size, used_phys, used,ring_size, ring_phys,ring)；
调用vhost_virtqueue_set_addr设置相关地址；Virtio的vring空间就映射到了Host的Kernel中

8. vhost和KVM是两个独立的内核模块，
9. vhost最核心处就在于将Guest中的virtio用于传输层的vring队列空间通过mapping方式与Host Kernel进行了共享，
这样数据就不需要通过多次的拷贝，直接进入了Kernel；通过io event事件机制进行了收发方向的通告，使vhost与Guest达到很好的配合。
