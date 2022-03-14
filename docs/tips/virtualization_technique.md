### 刘奇报告：下一代的混合云架构

1. VMware ESXi是VMware的裸机虚拟机管理程序。VMware ESXi是以ISO形式提供的软件，可直接安装在裸金属物理硬件上，ESXi把硬件资源虚拟化出来
提供很多的VM虚拟机，然后使用vCenter Server管理程序，把VM虚拟机提供给用户。VM的迁移是使用Vmotion支持热迁移。

2. vSphere:24TB内存，768个CPU(太强了)
3. vmWare内部的k8s叫做Tanzu,可以直接运行在物理机上
4. SmartNIC：智能网卡，类似一个CPU，使其运行ESXi,做硬件的虚拟化，做安全隔离,只管了存储和网络，将其池化提供给上层的ESXi和虚拟机,然后在CPU上运行另一个ESXi提供虚拟化。
5. 

### Project Thunder / Bitfusion (DLA: Deep  learning AI)
1. 把GPU池化，通过网络把GPU资源释放出来（把对CUDA的调用拦截，然后进行调度，remaping到特定的GPU去执行，返回结果）
2. 做硬件DLA加速
3. 
