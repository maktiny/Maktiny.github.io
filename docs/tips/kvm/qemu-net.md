#### tap设备的创建
1. net client的建立之前，需要先创建Qemu内部的hub和对应的port，来关联每一个net client，
而对于每个创建的-net类型的设备都是可以可以配置其接口的vlan号，从而控制数据包在其中
配置的vlan内部进行转发，从而做到多个虚拟设备之间的switch。nic设备与hub port相关联.

```c
//qemu的main()函数
main()
   ------->net_init_clients() //遍历配置参数，为每一个网络配置进行初始化
                -------->net_init_client()
		           ---->net_client_init()
			          ----->net_client_init1()
				           ----->net_hub_add_port()//查找或创建一个hub
                                           ------>net_client_init_fun[opts->kind])//调用对应网络设备的初始化函数
static int (* const net_client_init_fun[NET_CLIENT_OPTIONS_KIND_MAX])(
    const NetClientOptions *opts,
    const char *name,
    NetClientState *peer) = {
        [NET_CLIENT_OPTIONS_KIND_NIC]       = net_init_nic,
#ifdef CONFIG_SLIRP
        [NET_CLIENT_OPTIONS_KIND_USER]      = net_init_slirp,
#endif
        [NET_CLIENT_OPTIONS_KIND_TAP]       = net_init_tap,
        [NET_CLIENT_OPTIONS_KIND_SOCKET]    = net_init_socket,
#ifdef CONFIG_VDE
        [NET_CLIENT_OPTIONS_KIND_VDE]       = net_init_vde,
#endif
        [NET_CLIENT_OPTIONS_KIND_DUMP]      = net_init_dump,
#ifdef CONFIG_NET_BRIDGE
        [NET_CLIENT_OPTIONS_KIND_BRIDGE]    = net_init_bridge,
#endif
        [NET_CLIENT_OPTIONS_KIND_HUBPORT]   = net_init_hubport,
};



net_init_tap()//判断是否需要在加载设置好的脚本来初始化网络设备
     --->net_tap_init()
          ---->tap_open()//打开网络设备字符设备文件(linux一切都是文件)
          ---->launch_script()//如果有脚本，执行相应的脚本(execv()系统调用)

net_init_bridge()
   --->net_tap_fd_init()   file: tap.c, line: 325
          --->tap_read_poll()  file: tap.c, line: 81
               --->tap_update_fd_handler()  file: tap.c, line: 72
                    ---> qemu_set_fd_handler2()//Tap设备的事件通知加入了io_handlers的事件监听列表中,
	                                  //fd_read事件对应的动作为tap_send(),fd_write事件对应的动作为tap_writable()。
                          ----->QLIST_INSERT_HEAD(&io_handlers, ioh, next);   file: iohandler.c, line: 72
```

#### IO事件监听
1. 网络中使用的<mark>poll,select </mark>在这里体现,poll最多可以打开2048个fd
```c
main() //Qemu的Main函数通过一系列的初始化，并创建线程进行VM的启动，最后来到了main_loop()
  --->main_loop()
       --->main_loop_wait() //死循环，如果qemu没有相应的请求(eg. shutdown)，则一直循环等待IO
              ---->qemu_iohandler_fill()  
              ---->os_host_main_loop_wait()  
                          ----->select(nfds + 1, &rfds, &wfds, &xfds, tvarg)   <----此处对注册的源进行监听，包括Tap fd;
              ---->qemu_iohandler_poll()   <---调用事件对应动作进行处理read,write等；
```

#### 虚拟网卡的初始化

```c

static TypeInfo e1000_info = {
    .name          = "e1000",
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(E1000State),
    .class_init    = e1000_class_init,
};


static void e1000_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->init = pci_e1000_init;
    k->exit = pci_e1000_uninit;
    k->romfile = "pxe-e1000.rom";
    k->vendor_id = PCI_VENDOR_ID_INTEL;
    k->device_id = E1000_DEVID;
    k->revision = 0x03;
    k->class_id = PCI_CLASS_NETWORK_ETHERNET;
    dc->desc = "Intel Gigabit Ethernet";
    dc->reset = qdev_e1000_reset;
    dc->vmsd = &vmstate_e1000;
    dc->props = e1000_properties;
}


pci_e1000_init()
    ---->e1000_mmio_setup(d);        <-------e1000的mmio访问建立
    ---->pci_register_bar(&d->dev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &d->mmio);   <-------注册mmio空间
    ---->pci_register_bar(&d->dev, 1, PCI_BASE_ADDRESS_SPACE_IO, &d->io);   <-------注册pio空间
    ---->d->nic = qemu_new_nic(&net_e1000_info, &d->conf, object_get_typename(OBJECT(d)), d->dev.qdev.id, d);   
    <----初始化nic信息，并注册虚拟网卡的相关操作函数，结构如下，同时创建了与虚拟网卡对应的net client结构。在
    ---->add_boot_device_path(d->conf.bootindex, &pci_dev->qdev, "/ethernet-phy@0");   加入系统启动设备配置中
```


##### guest os的收包(I/O虚拟化)
1. Qemu主线程通过监听Tap设备文件读写事件来收发数据包，当有属于Guest OS的数据包在Host中收到后，
Host根据配置通过Bridge，Tap设备来到了Qeumu的用户态空间，Qemu通过调用了预先注册的Tap的读事件处理函数进行处理.

```c
tap_send()
 ---->tap_read_packet()     通过read从/net/dev/tun的fd中读取数据包
 ---->qemu_send_packet_async()      
          ------->qemu_send_packet_async_with_flags()   
                       -------->qemu_net_queue_send()     
                                   -------->qemu_net_queue_deliver()    
                                                    -------->qemu_deliver_packet()
                                                                 ------>ret = nc->info->receive()
                                                                                        |
										        |
static NetClientInfo net_hub_port_info = {						|
    .type = NET_CLIENT_OPTIONS_KIND_HUBPORT,						|
    .size = sizeof(NetHubPort),								|
    .can_receive = net_hub_port_can_receive,						|
    .receive = net_hub_port_receive,          <-----------------------------------------|
    .receive_iov = net_hub_port_receive_iov,
    .cleanup = net_hub_port_cleanup,
};
net_hub_port_receive()
        --------->net_hub_receive()//遍历hub的所有的port，把数据广播出去
                     ------->qemu_send_packet()
                                 --->qemu_send_packet_async()    
				        .........
					------>ret = nc->info->receive()//对应e1000_receive()---->在(root态)中设置一个收包中断，中断guest os。
e1000_receive()
     ---->pci_dma_write()//模拟DMA，网络驱动向guest内核空间写入接受到的信息
     ---->set_ics(s, 0, n)//设置中断，guest os中断之后把数据复制到用户空间
```


##### Guest OS的发包
1. 设备的模拟是在Qemu中进行的，KVM对该中异常退出无法处理，会将该退出原因注入给Qemu来处理qemu_kvm_wait_io_event() 
2. Qemu通过对触发io exit的地址的范围检测，找到对应的PIO/MMIO的地址空间，并调用地址空间注册时的一系列对应寄存器操作处理函数

```c

```

