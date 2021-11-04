## linux Ext4 文件系统简介

1. 参考：https://blog.csdn.net/cumj63710/article/details/107393126
2. 参考：https://blog.csdn.net/qq_40174198/article/details/109294578?spm=1001.2101.3001.6650.10&utm_medium=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-10.no_search_link&depth_1-utm_source=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-10.no_search_link
3. 参考：https://blog.csdn.net/RJ0024/article/details/110492406?spm=1001.2101.3001.6650.15&utm_medium=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-15.no_search_link&depth_1-utm_source=distribute.pc_relevant.none-task-blog-2%7Edefault%7EBlogCommendFromBaidu%7Edefault-15.no_search_link

### Ext 文件的发展史
1. MINIX : 微机的一个非常小的Unix操作系统，最多能处理14个字符的文件名，只能处理 64MB 的存储空间
2. EXT1: 第一个利用虚拟文件系统, 2GB存储空间并处理255个字符的文件
3. EXT2: 商业级文件系统, GB级别的最大文件大小和TB级别的文件系统大小
4. EXT3 : 增加日志功能
5. EXT4：提供更佳的性能和可靠性,更大的文件系统和更大的文件、无限数量的子目录、Extents、多块分配、延迟分配,快速 fsck、日志校验，No Journaling模式

##### MBR分区和 GPT分区
1. MBR的意思是“主引导记录”，是IBM公司早年间提出的。它是存在于磁盘驱动器开始部分的一个特殊的启动扇区。
这个扇区包含了引导程序(grub)和已安装的操作系统系统信息。
2. GPT的意思是GUID Partition Table，即“全局唯一标识磁盘分区表”。它是另外一种更加先进新颖的磁盘组织方式，
一种使用UEFI启动的磁盘组织方式。因为其更大的支持内存（mbr分区最多支持2T的磁盘，GPT支持2T以上）

###### BIOS + MBR 启动系统
1. BIOS下启动操作系统之前，必须从硬盘上指定扇区读取系统启动代码
（包含在MBR主引导记录中），然后从活动分区中引导启动操作系统，所以在BIOS下引导安装Windows
操作系统，我们不得不使用一些工具（DiskGenius）对硬盘进行配置以达到启动要求
（即建立MBR硬盘主引导和活动分区


###### UEFI + GPT 启动系统
1. UEFI之所以比BIOS强大，是因为UEFI本身已经相当于一个微型操作系统，其带来的便利之处在于：首先，UEFI已具备文件系统
（文件系统是操作系统组织管理文件的一种方法，直白点说就是把硬盘上的数据以文件的形式呈现给用户。
Fat32、NTFS都是常见的文件系统类型）的支持，它能够直接读取FAT分区中的文件；其次，
可开发出直接在UEFI下运行的应用程序，这类程序文件通常以efi结尾
2. U盘启动使用的就是UEFI的方式


##### 启动linux系统步骤
1. 开机之后，处理器进入实模式，实模式采用段式内存管理，并没有开启分页机制(CR3没有置位)
内存被分成固定的64k大小的块
2. 然后开始跳转到BIOS的入口地址开始执行。BIOS执行初始化和硬件检查之后，开始寻找引导设备(程序)
如果存在MBR分区，则引导扇区储存在第一个扇区(512字节)的头446字节，引导扇区的最后必须是
0x55 和 0xaa ，这2个字节称为魔术字节（Magic Bytes)，如果 BIOS 看到这2个字节，就知道这个设备是一个可引导设备
3. BIOS把系统控制权移交给引导程序，引导程序运行在实模式下。
4. 引导程序有GRUB2 和syslinux,这里介绍GRUB2.
5. GRUB 置于 normal 模式，在这个模式中，grub_normal_execute (from grub-core/normal/main.c) 将被调用以完成最后的准备工作，
然后显示一个菜单列出所用可用的操作系统。当某个操作系统被选择之后，grub_menu_execute_entry 开始执行，
它将调用 GRUB 的 boot 命令，来引导被选中的操作系统。
就像 kernel boot protocol 所描述的，引导程序必须填充 kernel setup header 
（位于 kernel setup code 偏移 0x01f1 处） 的必要字段。kernel setup header的定义开始于 arch/x86/boot/header.S
6. kernel的setup()函数初始化硬件设备和内核运行环境，设置CR0的PE位为0,从实模式切换到保护模式，跳转到startup_32，调用startup_32()函数继续一些初始化的工作
7. startup_32()函数调用start_kernel()，该函数完成内核的初始化，到这里linux内核才起来开始运行。

### Ext4的磁盘布局
![2021-11-03 14-41-19 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1gw1yk8pxvnj30py0cc784.jpg)

![2021-11-03 14-14-17 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1gw1ykmjk46j30pm07eq4f.jpg)

1. Ext4文件系统把整个分区划分成各个block group（块组）
2. 1024 bytes 的 Group 0 Padding（boot block）只有 块组0 有，用于装载该分区的操作系统。
 MBR 为主引导记录用来引导计算机。在计算机启动时，BIOS 读入并执行 MBR，MBR 作的第一件事
 就是确定活动分区(这对应于双系统的计算机开机时选择启动项，单系统的直接就能确定了
 所以就不需要选择)，读入活动分区的引导块(Boot block)，引导块再加载该分区中的操作系统
![2021-11-03 16-04-27 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShgy1gw20vn1z2mj30n9070acd.jpg)

```
ext4_super_block  超级块
ext4_group_desc 组描述符
ext4_inode 索引节点 
inode table 索引节点表是struct ext4_inode的线性数组
```
3. 符号连接的路径名小于60B,存放在索引节点的i_blocks字段,大于60B就需要分配数据块
4. 设备文件，管道，套接字等特殊文件不需要数据块，所有信息存储在索引节点。

###### 索引节点的增强属性 
1. inode索引节点的大小一般128B，当需要增加属性的时候，就会
使用inode的i_file_acl_lo字段指向增强属性。
```
##  索引节点增强属性描述符(属性名，属性值) 为了实现访问控制列表

struct ext4_xattr_entry {
	__u8	e_name_len;	/* length of name */
	__u8	e_name_index;	/* attribute name index */
	__le16	e_value_offs;	/* offset in disk block of value */
	__le32	e_value_inum;	/* inode in which the value is stored */
	__le32	e_value_size;	/* size of attribute value */
	__le32	e_hash;		/* hash value of name and value */
	char	e_name[];	/* attribute name */
};

ext4_xattr_set() ext4_xattr_get() ext4_xattr_list_entries()等函数处理该属性。

```

###### 目录
1. 目录是一种特殊的文件，这种文件的数据块内存放的数据是目录名称和索引节点
```
## 目录项结构
struct ext4_dir_entry_2 {
	__le32	inode;			/* Inode number */
	__le16	rec_len;		/* Directory entry length */
	__u8	name_len;		/* Name length 最大255B*/ 
	__u8	file_type;		/* See file type macros EXT4_FT_* below */
	char	name[EXT4_NAME_LEN];	/* File name */
};

```
