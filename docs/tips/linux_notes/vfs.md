## VFS super_block
1. VFS是linux 与具体的文件系统之间的标准接口，使得linux对各种文件形式都有一个很好的
兼容性。
2.  文件对象 file 和目录项对象 dentry在磁盘中内有映像，没有脏数据属性
每次打开文件的时候，动态创建。而索引节点在磁盘上由映像。
对文件的改动，是通过把文件具体内容所在的页，写回磁盘实现的(写时复制)。


### 目录项高速缓存
```
          目录项状态

        空状态： 由slab分配器处理
        未使用状态：d_inode 仍然指向索引节点
            
        正使用状态：
        负状态：与索引节点取消关联。 
```
1. 未使用目录项对象驻留内存的高速缓冲LRU双向链表中，最近最少使用的项在链表的尾部,
当目录项高速缓存不足，链表表尾删除元素。


### 进程的命名空间 
- 参考：https://blog.csdn.net/gatieme/article/details/51383322
1. PID,IPC,Network等系统资源不再是全局性的，而是属于特定的Namespace。
每个Namespace里面的资源对其他Namespace都是透明的。**要创建新的Namespace，
只需要在调用clone时指定相应的flag标志CLONE_NEWNS**。Linux Namespaces机制为实现基于容器的虚拟
化技术提供了很好的基础，LXC（Linux containers）就是利用这一特性实现了资源的隔离。
不同Container内的进程属于不同的Namespace，彼此透明，互不干扰。
下面我们就从clone系统调用的flag出发，来介绍各个Namespace。

### 文件系统的安装
1. 一个文件系统可以被安装n次，可以通过n个安装点进行访问，但是一种文件系统只有一个super_block
对象。
2. 同一个安装点的文件系统可以覆盖，已经使用的先前安装下的文件和目录的进程可以继续使用。

### vfsmount 已安装文件系统描述符

