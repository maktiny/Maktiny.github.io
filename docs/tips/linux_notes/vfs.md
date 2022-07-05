## VFS 虚拟文件系统
1. VFS是linux 与具体的文件系统之间的标准接口，使得linux对各种文件形式都有一个很好的
兼容性。
2. 文件对象 file 和目录项对象 dentry在磁盘中没有映像，没有脏数据属性
每次打开文件的时候，动态创建。而索引节点在磁盘上有映像。
对文件的改动，是通过把文件具体内容所在的页，写回磁盘实现的(写时复制)。
3. Linux内核能够发现真实的文件系统，那么必须先使用 register_filesystem() 函数注册文件系统
![2022-05-08 17-53-28 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h215aob60zj30tp0mf0v5.jpg)

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
```


### 挂载点
1. mount 和vfsmount 以及spuer_block的关系
![2022-05-31 10-05-05 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h2rd5sk808j30kg0dcwht.jpg)
```c


struct mount {
	struct hlist_node mnt_hash;
	struct mount *mnt_parent;//装载点所在的父文件系统
	struct dentry *mnt_mountpoint;//父文件系统的dentry
	struct vfsmount mnt;//vfs中有指针指向super_block
	union {
		struct rcu_head mnt_rcu;
		struct llist_node mnt_llist;
	};
#ifdef CONFIG_SMP
	struct mnt_pcp __percpu *mnt_pcp;
#else
	int mnt_count;
	int mnt_writers;
#endif
	struct list_head mnt_mounts;	/* list of children, anchored here */
	struct list_head mnt_child;	/* and going through their mnt_child */
	struct list_head mnt_instance;	/* mount instance on sb->s_mounts */
	const char *mnt_devname;	/* Name of device e.g. /dev/dsk/hda1 */
	struct list_head mnt_list;
	struct list_head mnt_expire;	/* link in fs-specific expiry list */
	struct list_head mnt_share;	/* circular list of shared mounts */
	struct list_head mnt_slave_list;/* list of slave mounts */
	struct list_head mnt_slave;	/* slave list entry */
	struct mount *mnt_master;	/* slave is on master->mnt_slave_list */
	struct mnt_namespace *mnt_ns;	/* containing namespace */
	struct mountpoint *mnt_mp;	/* where is it mounted */
	union {
		struct hlist_node mnt_mp_list;	/* list mounts with the same mountpoint */
		struct hlist_node mnt_umount;
	};
	struct list_head mnt_umounting; /* list entry for umount propagation */
#ifdef CONFIG_FSNOTIFY
	struct fsnotify_mark_connector __rcu *mnt_fsnotify_marks;
	__u32 mnt_fsnotify_mask;
#endif
	int mnt_id;			/* mount identifier */
	int mnt_group_id;		/* peer group identifier */
	int mnt_expiry_mark;		/* true if marked for expiry */
	struct hlist_head mnt_pins;
	struct hlist_head mnt_stuck_children;
} __randomize_layout;



struct vfsmount {
	struct dentry *mnt_root;	/* root of the mounted tree */
	struct super_block *mnt_sb;	/* pointer to superblock */
	int mnt_flags;
	struct user_namespace *mnt_userns;
} __randomize_layout;

```

### super_block
1. VFS 定义了一个名为 超级块（super_block)的数据结构来描述具体的文件系统，
内核是通过超级块来认知具体的文件系统的，一个具体的文件系统会对应一个超级块结构
2. 每个装载点mount对应着一个super_block,虽然可能两个装载点的文件系统类型相同，但是两个装载点在不同的分区上

```c
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
2. 在打开文件的时候动态的创建dentry对象，并缓存到内存的目录项缓存，并没有实际对应的磁盘上的描述,为了快速查找，也就是只有打开文件的目录有dentry实例


```c
struct dentry {
    ....................
    struct inode  * d_inode;    // 目录项对应的inode
    struct dentry * d_parent;   // 当前目录项对应的父目录
    ...................
    struct qstr d_name;         // 目录的名字，qstr是内核的一个字符包装器，是一个char*的指针和长度
    unsigned long d_time;
    struct dentry_operations  *d_op; // 目录项的辅助方法
    struct super_block * d_sb;       // 所在文件系统的超级块对象
    ...
    union {
		struct list_head d_lru;		/* LRU list 所有未使用的dentry链接形成LRU链表，适当的时候删除*/
		// 未使用目录项对象驻留内存的高速缓冲LRU双向链表中，最近最少使用的项在链表的尾部,
                //当目录项高速缓存不足，链表表尾删除元素。


		wait_queue_head_t *d_wait;	/* in-lookup ones only */
	};
    unsigned char d_iname[DNAME_INLINE_LEN]; // 当目录名不超过16个字符时使用
    ................................
};


static unsigned int d_hash_shift __read_mostly;
//内存中的所有dentry实例都保存到dentry_hashtable hash表中，使用d_hash解决hash冲突
static struct hlist_bl_head *dentry_hashtable __read_mostly;

static inline struct hlist_bl_head *d_hash(unsigned int hash)
{
	return dentry_hashtable + (hash >> d_hash_shift);
}





static DEFINE_PER_CPU(long, nr_dentry);

//所有未使用的dentry(引用计数d_count = 0)的对象都放到nr_dentry_unused链表中
static DEFINE_PER_CPU(long, nr_dentry_unused);
static DEFINE_PER_CPU(long, nr_dentry_negative);

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
2. 一个(64位系统)进程默认可以打开64个文件.
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
	struct file_ra_state	f_ra;//保存预读相关的特征信息
  ..................................
}



struct fdtable { //初始化的时候指向files_struct中相应的成员变量

	unsigned int max_fds;	
	struct file __rcu **fd;      /* current fd array */
	unsigned long *close_on_exec;
	unsigned long *open_fds;
	unsigned long *full_fds_bits;
	struct rcu_head rcu;
};
//fdtable->fd 通常指向 files_struct->fd_array，该数组的索引就是文件描述符
//通常第一个元素（索引为 0）时进程的标准输入文件，第二个是标准输出文件（索引为 1），第三个是标准错误文件（索引为 2）

struct task_struct {

   
	/* Filesystem information: */
	struct fs_struct		*fs;

	/* Open file information: */
	struct files_struct		*files;

}

/*
 * Open file table structure
 */
struct files_struct {
  /*
   * read mostly part
   */
	atomic_t count;
	bool resize_in_progress;
	wait_queue_head_t resize_wait;

	struct fdtable __rcu *fdt;
	struct fdtable fdtab;
  /*
   * written part on a separate cache line in SMP
   */
	spinlock_t file_lock ____cacheline_aligned_in_smp;
	unsigned int next_fd;//下一次打开新文件是使用的文件描述
	unsigned long close_on_exec_init[1];//exec时关闭文件描述符位图
	unsigned long open_fds_init[1];//打开文件描述符位图
	unsigned long full_fds_bits_init[1];
	struct file __rcu * fd_array[NR_OPEN_DEFAULT];//指向进程打开的file的指针数组(数组默认大小64)
	//如果进程打开的文件大于64个，使用fs/file.c中的expand_files(）函数扩展整个fd_array数组以及相关的位图大小(新建数据结构，把原来的数据复制过去)
};



struct fs_struct {
	int users;
	spinlock_t lock;
	seqcount_spinlock_t seq;
	int umask;//掩码，用于设置新的文件权限
	int in_exec;
	struct path root, pwd;//指定了根目录和当前工作目录
} __randomize_layout;
```


### 进程的命名空间 
- 参考：https://blog.csdn.net/gatieme/article/details/51383322
1. PID,IPC,Network等系统资源不再是全局性的，而是属于特定的Namespace。
每个Namespace里面的资源对其他Namespace都是透明的。**要创建新的Namespace，
只需要在调用clone时指定相应的flag标志CLONE_NEWNS**。Linux Namespaces机制为实现基于容器的虚拟
化技术提供了很好的基础，LXC（Linux containers）就是利用这一特性实现了资源的隔离。
不同Container内的进程属于不同的Namespace，彼此透明，互不干扰.

### 文件系统的安装
1. 一个文件系统可以被安装n次，可以通过n个安装点进行访问，但是一种文件系统在同一个安装点只有一个super_block
对象,一个文件系统可以有几个super_block对象，不同的分区（home 和root）
2. 同一个安装点的文件系统可以覆盖，已经使用的先前安装下的文件和目录的进程可以继续使用。


```c
//挂载的操作使用系统调用mount
            mount()
		      |
	      do_mount()
		     |
		path_mount()
		  |
         do_new_mount（）
   
//卸载操作
         umount()
	       |
	   ksys_umount()
	      |
	   path_umount()
	     |
	  do_umount()
```

### 伪文件系统
1. 伪文件系统从内核数据结构包含的信息生成文件内容，以文件系统的方式为访问系统内核数据的操作提供接口。
2. 伪文件系统不代表真实的物理设备,内核提供了装载标志MS_NOUSER，使伪文件系统不可装载.比如sysfs ，proc就是伪文件系统。
3. 有些文件系统是可以读写的，sysctl 命令专用于查看或设定 /proc/sys 目录下参数的值， 能修改的就是 /proc/sys 目录下的参数。
4. 伪文件系统的作用是对一些操作系统中的元素进行封装，和普通的文件统一接口，如块设备bdevfs，管道文件pipefs，套接字socketfs等。通过这种方式的统一封装，才实现了Linux一切皆文件的思想
