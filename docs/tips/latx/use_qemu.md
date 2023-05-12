## 编译qemu的源码
```c
//系统态
//可能会出现很多依赖问题,把缺少的依赖库手动安装即可
../configure --target-list=x86_64-softmmu  --enable-debug --disable-werror --enable-kvm --enable-bpf --enable-debug-info --enable-vhost-net --enable-vhost-kernel --enable-vhost-user --enable-vhost-vdpa --disable-spice-protocol --disable-xen


//依赖库
sudo apt-get install git-email
sudo apt-get install libaio-dev libbluetooth-dev libcapstone-dev libbrlapi-dev libbz2-dev
sudo apt-get install libcap-ng-dev libcurl4-gnutls-dev libgtk-3-dev
sudo apt-get install libibverbs-dev libjpeg8-dev libncurses5-dev libnuma-dev
sudo apt-get install librbd-dev librdmacm-dev
sudo apt-get install libsasl2-dev libsdl2-dev libseccomp-dev libsnappy-dev libssh-dev
sudo apt-get install libvde-dev libvdeplug-dev libvte-2.91-dev libxen-dev liblzo2-dev
sudo apt-get install valgrind xfslibs-dev 
sudo apt-get install libnfs-dev libiscsi-dev
```


## 调试qemu
```c
//把GDB挂到qemu的二进制文件qemu-system-x86_64上进行调试qemu.
gdb -q --args /home/liyi/programs/qemu/qemu-6.2.0-rc2/build_x86/qemu-system-x86_64 -s -S -kernel arch/x86/boot/bzImage \
                                -boot c -m 2049M -hda buildroot/output/images/rootfs.ext4 \
                                -append "root=/dev/sda rw console=ttyS0,115200 acpi=off nokaslr" \
                                -serial stdio -display none



    //如果需要调试内核,需要在另一个终端使用 GDB tcp:1234进行调试
    $ gdb vmlinux
    $ target remote:1234 

   //打断点的另外一种方式是内链汇编: asm("int3")
```

### 设备直通

```c
在QEMU/KVM环境中，VFIO是一种机制，允许将物理设备（如显卡或网卡）直接分配给虚拟机，从而提高性能。要启用VFIO，需要遵循以下步骤：

检查CPU支持IOMMU（Input-Output Memory Management Unit）。可以通过以下命令检查：

grep -E 'svm|vmx' /proc/cpuinfo
如果输出中有'svm'或'vmx'，则CPU支持IOMMU。

安装必要的软件包。在Ubuntu中，可以使用以下命令：

sudo apt-get install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils
配置IOMMU。在Linux上，需要编辑/boot/grub/grub.cfg文件，并在kernel行中添加“intel_iommu=on”或“amd_iommu=on”。例如：

linux /boot/vmlinuz-4.4.0-116-generic root=UUID=e0d950b0-6f9a-4ab7-998a-96f3c3d4d4b0 ro quiet splash intel_iommu=on
确认设备支持VFIO。可以使用以下命令列出PCI设备：

lspci
找到要分配给虚拟机的设备，并记下其ID号码。

将VFIO驱动程序加载到内核中。可以使用以下命令：

sudo modprobe vfio-pci
创建一个VFIO设备配置文件。可以使用以下命令：

sudo nano /etc/modprobe.d/vfio.conf
在文件中添加以下行，其中“<ID号码>”是在步骤4中找到的设备ID：

options vfio-pci ids=<ID号码>
重启计算机以使配置生效。

完成这些步骤后，您应该能够将物理设备分配给虚拟机。在QEMU命令行中，使用“-device vfio-pci”选项来分配设备。例如：

qemu-system-x86_64 -m 2048 -cpu host -smp 2 -enable-kvm \
-device vfio-pci,host=01:00.0,multifunction=on \
-drive file=/path/to/vm-image,if=virtio
在这个例子中，显卡设备被分配给虚拟机。请注意，“host=01:00.0”参数指定要分配的设备，而“multifunction=on”参数指示QEMU分配设备的所有功能（例如显卡的视频输出和音频输出功能）。

```
