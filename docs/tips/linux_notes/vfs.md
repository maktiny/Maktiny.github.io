## VFS super_block
1. VFS是linux 与具体的文件系统之间的标准接口，使得linux对各种文件形式都有一个很好的
兼容性。
2. 文件对象 file 和目录项对象 dentry在磁盘中内有映像，没有脏数据属性
每次打开文件的时候，动态创建。而索引节点在磁盘上由映像。
对文件的改动，是通过把文件具体内容所在的页，写回磁盘实现的(写时复制)。
3. Linux内核能够发现真实的文件系统，那么必须先使用 register_filesystem() 函数注册文件系统
![2022-05-08 17-53-28 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h215aob60zj30tp0mf0v5.jpg)

### super_block
1. VFS 定义了一个名为 超级块（super_block)的数据结构来描述具体的文件系统，
内核是通过超级块来认知具体的文件系统的，一个具体的文件系统会对应一个超级块结构

```c
 //文件系统的类型
struct file_system_type {
	const char *name;
	int fs_flags;
#define FS_REQUIRES_DEV		1 
#define FS_BINARY_MOUNTDATA	2
#define FS_HAS_SUBTYPE		4
#define FS_USERNS_MOUNT		8	/* Can be mounted by userns root */
#define FS_DISALLOW_NOTIFY_PERM	16	/* Disable fanotify permission events */
#define FS_ALLOW_IDMAP         32      /* FS has been updated to handle vfs idmappings. */
#define FS_THP_SUPPORT		8192	/* Remove once all fs converted */
#define FS_RENAME_DOES_D_MOVE	32768	/* FS will handle d_move() during rename() internally. */
	int (*init_fs_context)(struct fs_context *);
	const struct fs_parameter_spec *parameters;
	struct dentry *(*mount) (struct file_system_type *, int,
		       const char *, void *);
	void (*kill_sb) (struct super_block *);
	struct module *owner;
	struct file_system_type * next;
	struct hlist_head fs_supers;
................................
}

//具体的文件系统描述符
struct super_block {
	struct list_head	s_list;		/* Keep this first */
	dev_t			s_dev;		/* search index; _not_ kdev_t */
	unsigned char		s_blocksize_bits;
	unsigned long		s_blocksize;
	loff_t			s_maxbytes;	/* Max file size */
	struct file_system_type	*s_type;//文件系统的类型，提供您读取super_block的方法
	const struct super_operations	*s_op;//文件系统相关的操作集合
	const struct dquot_operations	*dq_op;
	const struct quotactl_ops	*s_qcop;
	const struct export_operations *s_export_op;
	unsigned long		s_flags;

  .................................
}

```

### 目录项 dentry
1. 目录项的主要作用是方便查找文件。一个路径的各个组成部分，不管是目录还是普通的文件，都是一个目录项对象
```c
struct dentry {
    ....................
    struct inode  * d_inode;    // 目录项对应的inode
    struct dentry * d_parent;   // 当前目录项对应的父目录
    ...................
    struct qstr d_name;         // 目录的名字
    unsigned long d_time;
    struct dentry_operations  *d_op; // 目录项的辅助方法
    struct super_block * d_sb;       // 所在文件系统的超级块对象
    ...
    unsigned char d_iname[DNAME_INLINE_LEN]; // 当目录名不超过16个字符时使用
    ................................
};

```

### inode索引节点
1. 索引节点（inode） 是 VFS 中最为重要的一个结构，用于描述一
个文件的meta（元）信息，其包含的是诸如文件的大小、拥有者、创建时间、
磁盘位置等和文件相关的信息，所有文件都有一个对应的 inode 结构

```c

struct inode {
	umode_t			i_mode;
	unsigned short		i_opflags;
	kuid_t			i_uid;
	kgid_t			i_gid;
	unsigned int		i_flags;

#ifdef CONFIG_FS_POSIX_ACL
	struct posix_acl	*i_acl;
	struct posix_acl	*i_default_acl;
#endif

	const struct inode_operations	*i_op;//i_op 成员定义对目录相关的操作方法列表
	struct super_block	*i_sb;
	struct address_space	*i_mapping;

#ifdef CONFIG_SECURITY
	void			*i_security;
#endif

	/* Stat data, not accessed from path walking */
	unsigned long		i_ino;
	/*
	 * Filesystems may only read i_nlink directly.  They shall use the
	 * following functions for modification:
	 *
	 *    (set|clear|inc|drop)_nlink
	 *    inode_(inc|dec)_link_count
	 */
	union {
		const unsigned int i_nlink;
		unsigned int __i_nlink;
	};
	dev_t			i_rdev;
	loff_t			i_size;
u16			i_wb_frn_avg_time;
	u16			i_wb_frn_history;
#endif
...........................................................
#if defined(CONFIG_IMA) || defined(CONFIG_FILE_LOCKING)
	atomic_t		i_readcount; /* struct files open RO */
#endif
	union {
		const struct file_operations	*i_fop;	/* former ->i_op->default_file_ops */
    ///i_fop 成员则定义了对打开文件后对文件的操作方法列表
		void (*free_inode)(struct inode *);
	};

```

### 文件 file
1. 文件结构用于描述一个已打开的文件，其包含文件当前的读写偏移量，文件打开模式和文件操作函数列表等

```c

struct file {
	union {
		struct llist_node	fu_llist;
		struct rcu_head 	fu_rcuhead;
	} f_u;
	struct path		f_path;//路径
	struct inode		*f_inode;	/* cached value */所属的索引节点
	const struct file_operations	*f_op；//文件操作

	/*
	 * Protects f_ep, f_flags.
	 * Must not be taken from IRQ context.
	 */
	spinlock_t		f_lock;
	enum rw_hint		f_write_hint;
	atomic_long_t		f_count;//文件引用计数
	unsigned int 		f_flags;//标志位
	fmode_t			f_mode;//打开模式
	struct mutex		f_pos_lock;
	loff_t			f_pos;//读写偏移量
	struct fown_struct	f_owner;//所属者信息
	const struct cred	*f_cred;
	struct file_ra_state	f_ra;
  ..................................
}
```

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

