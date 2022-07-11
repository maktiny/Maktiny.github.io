### 字符设备驱动程序
1. 设备号dev是一个范围，可以由宏解析出主设备号和次设备号。
2. 设备号在统一范围的所有设备文件由同一个设备驱动程序处理。
3. 字符设备一般不用缓冲，使用硬件设备提供的寄存器和中断即可与cpu通信
4. 声卡等顺序设备的缓冲使用循环缓冲区。


```c
  /*
  *     字符设备驱动程序描述符
  * cdev_alloc()分配cdev描述符
  * cdev_add()在设备驱动模型中注册cdev描述符
  **/
struct cdev {
	struct kobject kobj;
	struct module *owner;
	const struct file_operations *ops;
	struct list_head list;
	dev_t dev;//设备号
	unsigned int count;
} __randomize_layout;

//参考：static struct kobj_map *cdev_map;


/*
*cdev_map是一个散列表，cdev_add()函数调用kobj_map()
*函数，把指定的设备号范围加入到散列表中，每注册一个cdev
*字符设备驱动程序，就需要把他插入到cdev_map中
*/
static struct kobj_map *cdev_map;//用于维护所有字符设备驱动
struct kobj_map {
	struct probe {
		struct probe *next;
		dev_t dev;
		unsigned long range;
		struct module *owner;
		kobj_probe_t *get;
		int (*lock)(dev_t, void *);
		void *data;
	} *probes[255];
	struct mutex *lock;
};


 /*
 * 为了记录已经分配的设备号， 使用散列表chrdevs
 * 两个不同的设备号范围可以使用同一个主设备号，
 * 使用冲突链表char_device_struct结构记录冲突。
 **/
static struct char_device_struct {
	struct char_device_struct *next;
	unsigned int major;
	unsigned int baseminor;
	int minorct;
	char name[64];
	struct cdev *cdev;		/* will die */
} *chrdevs[CHRDEV_MAJOR_HASH_SIZE];

register_chrdev()实际调用__register_chrdev()，该函数会进行字符设备的注册操作
regietr_chrdev_region()和alloc_cgrdev_region()//分配一个范围的设备号
```

### 磁盘的描述符 gendisk

```c
struct gendisk {
	/* major, first_minor and minors are input parameters only,
	 * don't use directly.  Use disk_devt() and disk_max_parts().
	 */
	int major;			/* major number of driver */
	int first_minor;
	int minors;                     /* maximum number of minors, =1 for
                                         * disks that can't be partitioned. */

	char disk_name[DISK_NAME_LEN];	/* name of major driver */

	unsigned short events;		/* supported events */
	unsigned short event_flags;	/* flags related to event processing */

	struct xarray part_tbl;### 磁盘分区表，分区表放在xarry中

	struct block_device *part0;

	const struct block_device_operations *fops;#磁盘注册的块设备操作函指针
	struct request_queue *queue;
	void *private_data;

	int flags;
	unsigned long state;
#define GD_NEED_PART_SCAN		0
#define GD_READ_ONLY			1
#define GD_DEAD				2

	struct mutex open_mutex;	/* open/close mutex */
	unsigned open_partitions;	/* number of open partitions */

	struct backing_dev_info	*bdi;
	struct kobject *slave_dir;
#ifdef CONFIG_BLOCK_HOLDER_DEPRECATED
	struct list_head slave_bdevs;
#endif
	struct timer_rand_state *random;
	atomic_t sync_io;		/* RAID */
	struct disk_events *ev;
#ifdef  CONFIG_BLK_DEV_INTEGRITY
	struct kobject integrity_kobj;
#endif	/* CONFIG_BLK_DEV_INTEGRITY */
#if IS_ENABLED(CONFIG_CDROM)
	struct cdrom_device_info *cdi;
#endif
	int node_id;
	struct badblocks *bb;
	struct lockdep_map lockdep_map;
	u64 diskseq;
};
```

### 通用块层的 bio结构
1. 通常用一个bio结构体来对应一个I/O请求
```c
/* bio中的每一个段是由bio_vec结构体描述*/
struct bio_vec {
	struct page	*bv_page;#指向段的页框中页的指针
	unsigned int	bv_len; #段的长度
	unsigned int	bv_offset; #段内偏移
};
 
struct bvec_iter {
	sector_t		bi_sector;	/* 扇区：x86中扇区一般512B,也有更大的。device address in 512 byte
						   sectors */
	unsigned int		bi_size;	/* residual I/O count */

	unsigned int		bi_idx;		/* 指向待传送的第一个段，不 断更新 */

	unsigned int            bi_bvec_done;	/* number of bytes completed in
						   current bvec */
};

 /*块设备描述IO操作的结构体*/
struct bio {
	struct bio		*bi_next;	/* request queue link */
	struct block_device	*bi_bdev;
	unsigned int		bi_opf;		/* bottom bits req flags,
						 * top bits REQ_OP. Use
						 * accessors.
						 */
	unsigned short		bi_flags;	/* BIO_* below */
	unsigned short		bi_ioprio;
	unsigned short		bi_write_hint;
	blk_status_t		bi_status;
	atomic_t		__bi_remaining;

	struct bvec_iter	bi_iter;

	bio_end_io_t		*bi_end_io;

	void			*bi_private;

  ......................

	unsigned short		bi_vcnt;	/* how many bio_vec's */

	/*
	 * Everything starting with bi_max_vecs will be preserved by bio_reset()
	 */

	unsigned short		bi_max_vecs;	/* max bvl_vecs we can hold */

	atomic_t		__bi_cnt;	/* pin count */

	struct bio_vec		*bi_io_vec;	/* the actual vec list */

	struct bio_set		*bi_pool;

	/*
	 * We can inline a number of vecs at the end of the bio, to avoid
	 * double allocations for a small number of bio_vecs. This member
	 * MUST obviously be kept at the very end of the bio.
	 */
	struct bio_vec		bi_inline_vecs[];
};

```
### 通用块层
1. 将对不同块设备的操作转换成对逻辑数据块的操作，也就是将不同的块设备都抽象成是一个数据块数组，而文件系统就是对这些数据块进行管理
2. 通用块层就是具体文件系统与具体的存储设备驱动之间的接口。由于不同的存储设备对硬件块的抽象不同，驱动也不同,
通用快层的出现就是为了屏蔽这种差异，像EXT4/NTFS这样的文件系统对任何的存储设备都可用，只需要存储设备的驱动开发遵从
通用块层的设计接口，把对文件的操作向通用块层注册即可。
3. 通用块层 将对不同块设备的操作转换成对逻辑数据块的操作，也就是将不同的块设备都抽象成是一个数据块数组，而文件系统就是对这些数据块进行管理
4. 通过对设备进行抽象后，不管是磁盘还是机械硬盘，对于文件系统都可以使用相同的接口对逻辑数据块进行读写操作
![2022-05-08 19-19-53 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h217tfgnesj30or0k70vg.jpg)

5. 通用块层使用 ll_rw_block()对逻辑块进行读写
```c
//bufer_head结构代表一个要进行读或者写的数据块, 一个buffer_head对应一个bio（需要用buffer_head去初始化bio结构体）
struct buffer_head {
	unsigned long b_state;		/* buffer state bitmap (see above) */
	struct buffer_head *b_this_page;/* circular list of page's buffers */
	struct page *b_page;		/* the page this bh is mapped to */

	sector_t b_blocknr;		/* start block number */
	size_t b_size;			/* size of mapping */
	char *b_data;			/* pointer to data within the page */

	struct block_device *b_bdev;
	bh_end_io_t *b_end_io;		/* I/O completion */
 	void *b_private;		/* reserved for b_end_io */
	struct list_head b_assoc_buffers; /* associated with another mapping */
	struct address_space *b_assoc_map;	/* mapping this buffer is
						   associated with */
	atomic_t b_count;		/* users using this buffer_head */
	spinlock_t b_uptodate_lock;	/* Used by the first bh in a page, to
					 * serialise IO completion of other
					 * buffers in the page */
};

void ll_rw_block(int op, int op_flags,  int nr, struct buffer_head *bhs[])
{
	int i;

	for (i = 0; i < nr; i++) {
		struct buffer_head *bh = bhs[i];

		if (!trylock_buffer(bh))
			continue;
		if (op == WRITE) {//写
			if (test_clear_buffer_dirty(bh)) {
				bh->b_end_io = end_buffer_write_sync;
				get_bh(bh);//增加buffer_head的引用计数，
				submit_bh(op, op_flags, bh);//将该buffer_head调用submit_bio()提交给I/O调度层，然后进行写入磁盘
				continue;
			}
		} else {
			if (!buffer_uptodate(bh)) {
				bh->b_end_io = end_buffer_read_sync;
				get_bh(bh);
				submit_bh(op, op_flags, bh);
				continue;
			}
		}
		unlock_buffer(bh);
	}
}
EXPORT_SYMBOL(ll_rw_block);


int submit_bh(int op, int op_flags, struct buffer_head *bh)
{
	return submit_bh_wbc(op, op_flags, bh, 0, NULL);
}
EXPORT_SYMBOL(submit_bh);



static int submit_bh_wbc(int op, int op_flags, struct buffer_head *bh,
			 enum rw_hint write_hint, struct writeback_control *wbc)
{
	struct bio *bio;

	BUG_ON(!buffer_locked(bh));
	BUG_ON(!buffer_mapped(bh));
	BUG_ON(!bh->b_end_io);
	BUG_ON(buffer_delay(bh));
	BUG_ON(buffer_unwritten(bh));

	/*
	 * Only clear out a write error when rewriting
	 */
	if (test_set_buffer_req(bh) && (op == REQ_OP_WRITE))
		clear_buffer_write_io_error(bh);

	bio = bio_alloc(GFP_NOIO, 1);

	fscrypt_set_bio_crypt_ctx_bh(bio, bh, GFP_NOIO);

	bio->bi_iter.bi_sector = bh->b_blocknr * (bh->b_size >> 9);
	bio_set_dev(bio, bh->b_bdev);
	bio->bi_write_hint = write_hint;

	bio_add_page(bio, bh->b_page, bh->b_size, bh_offset(bh));
	BUG_ON(bio->bi_iter.bi_size != bh->b_size);

	bio->bi_end_io = end_bio_bh_io_sync;
	bio->bi_private = bh;

	if (buffer_meta(bh))
		op_flags |= REQ_META;
	if (buffer_prio(bh))
		op_flags |= REQ_PRIO;
	bio_set_op_attrs(bio, op, op_flags);

	/* Take care of bh's that straddle the end of the device */
	guard_bio_eod(bio);

	if (wbc) {
		wbc_init_bio(wbc, bio);
		wbc_account_cgroup_owner(wbc, bh->b_page, bh->b_size);
	}

	submit_bio(bio);
	return 0;
}

submit_bio()-->submit_bio_noacct()--->__submit_bio_noacct()-->__submit_bio()调用gendisk硬盘注册时候函数submit_bio()把bio放到请求队列中

```
6. 请求队列struct request_queue中存放请求request

```c
struct request {
	struct request_queue *q;
	struct blk_mq_ctx *mq_ctx;
	struct blk_mq_hw_ctx *mq_hctx;

	unsigned int cmd_flags;		/* op and common flags */
	req_flags_t rq_flags;

	int tag;
	int internal_tag;

	/* the following two fields are internal, NEVER access directly */
	unsigned int __data_len;	/* total data len */
	sector_t __sector;		/* sector cursor */

	struct bio *bio; //
	struct bio *biotail;//当IO传输时，可以动态添加bio,只要biotail改变就可以

	struct list_head queuelist;

	/*
	 * The hash is used inside the scheduler, and killed once the
	 * request reaches the dispatch list. The ipi_list is only used
	 * to queue the request for softirq completion, which is long
	 * after the request has been unhashed (and even removed from
	 * the dispatch list).
	 */
	union {
		struct hlist_node hash;	/* merge hash */
		struct llist_node ipi_list;
	};

	/*
	 * The rb_node is only used inside the io scheduler, requests
	 * are pruned when moved to the dispatch queue. So let the
	 * completion_data share space with the rb_node.
	 */
	union {
		struct rb_node rb_node;	/* sort/lookup */
		struct bio_vec special_vec;
		void *completion_data;
		int error_count; /* for legacy drivers, don't use */
	};

	/*
	 * Three pointers are available for the IO schedulers, if they need
	 * more they have to dynamically allocate it.  Flush requests are
	 * never put on the IO scheduler. So let the flush fields share
	 * space with the elevator data.
	 */
	union {
		struct {
			struct io_cq		*icq;
			void			*priv[2];
		} elv;

		struct {
			unsigned int		seq;
			struct list_head	list;
			rq_end_io_fn		*saved_end_io;
		} flush;
	};

	struct gendisk *rq_disk;
	struct block_device *part;
#ifdef CONFIG_BLK_RQ_ALLOC_TIME
	/* Time that the first bio started allocating this request. */
	u64 alloc_time_ns;
#endif
	/* Time that this request was allocated for this IO. */
	u64 start_time_ns;
	/* Time that I/O was submitted to the device. */
	u64 io_start_time_ns;

#ifdef CONFIG_BLK_WBT
	unsigned short wbt_flags;
#endif
	/*
	 * rq sectors used for blk stats. It has the same value
	 * with blk_rq_sectors(rq), except that it never be zeroed
	 * by completion.
	 */
	unsigned short stats_sectors;

	/*
	 * Number of scatter-gather DMA addr+len pairs after
	 * physical address coalescing is performed.
	 */
	unsigned short nr_phys_segments;

#if defined(CONFIG_BLK_DEV_INTEGRITY)
	unsigned short nr_integrity_segments;
#endif

#ifdef CONFIG_BLK_INLINE_ENCRYPTION
	struct bio_crypt_ctx *crypt_ctx;
	struct blk_ksm_keyslot *crypt_keyslot;
#endif

	unsigned short write_hint;
	unsigned short ioprio;

	enum mq_rq_state state;
	refcount_t ref;

	unsigned int timeout;
	unsigned long deadline;

	union {
		struct __call_single_data csd;
		u64 fifo_time;
	};

	/*
	 * completion callback.
	 */
	rq_end_io_fn *end_io;
	void *end_io_data;
};
```

### IO调度算法

1. Noop算法：新的请求被插入到request_queue的头或尾(FIFO队列)，下一个要处理的请求就是request_queue的开头元素

2. CFQ算法： 使用进程或线程组的PID做哈希，哈希值索引排序队列(排序和合并)，为每个进程分配一个排序队列(排序队列默认64个)
,相同进程分同步请求都放到一个请求队列，异步请求放到公共请求队列。每次执行一个进程的4个请求，进程之间的请求可以调度。

3. Deadline算法：使用两对读/写IO请求队列（FIFO队列）,新请求按方向同时插入到两个队列中，
，从1中拿一个请求插到调度队列的时候，先检查2.中的是否超时，如果已经超过一个阀值，
就会先处理超时请求。 这个阀值对于读请求时 5ms， 对于写请求时5s.

```
  1.  ------------ read queue   
      ------------ write queue

  2.  ------------ read deadline queue  -->定时
      ------------ write deadline queue


      ---------- 调度队列

```

3. Anticipatory预期算法: 预期算法是deadline的改进版，为每个读请求执行完之后预留默认6ms的时间
如果在窗口期内，收到相邻位置的读请求可以马上满足。

```c
 //IO调度算法使用elevator_type描述
struct elevator_type
{
	/* managed by elevator core */
	struct kmem_cache *icq_cache;

	/* fields provided by elevator implementation */
	struct elevator_mq_ops ops;

	size_t icq_size;	/* see iocontext.h */
	size_t icq_align;	/* ditto */
	struct elv_fs_entry *elevator_attrs;
	const char *elevator_name;
	const char *elevator_alias;
	const unsigned int elevator_features;
	struct module *elevator_owner;
#ifdef CONFIG_BLK_DEBUG_FS
	const struct blk_mq_debugfs_attr *queue_debugfs_attrs;
	const struct blk_mq_debugfs_attr *hctx_debugfs_attrs;
#endif

	/* managed by elevator core */
	char icq_cache_name[ELV_NAME_MAX + 6];	/* elvname + "_io_cq" */
	struct list_head list;
};
```

### 块设备驱动程序

```c
  //块设备驱动程序描述符
struct device_driver {
	const char		*name;
	struct bus_type		*bus;

	struct module		*owner;
	const char		*mod_name;	/* used for built-in modules */

	bool suppress_bind_attrs;	/* disables bind/unbind via sysfs */
	enum probe_type probe_type;

	const struct of_device_id	*of_match_table;
	const struct acpi_device_id	*acpi_match_table;

	int (*probe) (struct device *dev);
	void (*sync_state)(struct device *dev);
	int (*remove) (struct device *dev);
	void (*shutdown) (struct device *dev);
	int (*suspend) (struct device *dev, pm_message_t state);
	int (*resume) (struct device *dev);
	const struct attribute_group **groups;
	const struct attribute_group **dev_groups;

	const struct dev_pm_ops *pm;
	void (*coredump) (struct device *dev);

	struct driver_private *p;
};

 //块设备描述符
struct block_device {
	sector_t		bd_start_sect;
	struct disk_stats __percpu *bd_stats;
	unsigned long		bd_stamp;
	bool			bd_read_only;	/* read-only policy */
	dev_t			bd_dev;
	int			bd_openers;
	struct inode *		bd_inode;	/* will die */
	struct super_block *	bd_super;
	void *			bd_claiming;
	struct device		bd_device;
	void *			bd_holder;
	int			bd_holders;
	bool			bd_write_holder;
	struct kobject		*bd_holder_dir;
	u8			bd_partno;
	spinlock_t		bd_size_lock; /* for bd_inode->i_size updates */
	struct gendisk *	bd_disk;

	/* The counter of freeze processes */
	int			bd_fsfreeze_count;
	/* Mutex for freeze */
	struct mutex		bd_fsfreeze_mutex;
	struct super_block	*bd_fsfreeze_sb;

	struct partition_meta_info *bd_meta_info;
#ifdef CONFIG_FAIL_MAKE_REQUEST
	bool			bd_make_it_fail;
#endif
} __randomize_layout;
```
1. Linux 将块设备的 block_device 和 bdev 文件系统的块设备的 inode通过 struct bdev_inode 进行关联

```c

struct bdev_inode {
	struct block_device bdev;
	struct inode vfs_inode;
};


```


