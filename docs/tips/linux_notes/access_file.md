### 文件预读
1. 预读算法维护两个窗口，当前窗口和预读窗口，预读窗口内的页(还在传输中的页)紧挨着当前窗口内的页
2. 当顺序读时，启动文件预读算法。
```c
struct file_ra_state {
	pgoff_t start; //当前窗口的第一页的索引
	unsigned int size;// 当前窗口的页数
	unsigned int async_size;
	unsigned int ra_pages;//预读窗口的最大页数，0表示禁止预读，default=32页
	unsigned int mmap_miss;
	loff_t prev_pos;
};


```


###

```c

 //kiocb 用来跟踪同步和异步IO操作的完成状态
struct kiocb {
	struct file		*ki_filp; // IO操作的文件对象

	/* The 'ki_filp' pointer is shared in a union for aio */
	randomized_struct_fields_start

	loff_t			ki_pos; //进行IO操作的文件的当前位置
	void (*ki_complete)(struct kiocb *iocb, long ret, long ret2);
	void			*private;
	int			ki_flags;
	u16			ki_hint;
	u16			ki_ioprio; /* See linux/ioprio.h */
	union {
		unsigned int		ki_cookie; /* for ->iopoll */
		struct wait_page_queue	*ki_waitq; /* for async buffered IO */
	};

	randomized_struct_fields_end
};
/*
 * "descriptor" for what we're up to with a read.
 * This allows us to use the same read code yet
 * have multiple different users of the data that
 * we read from a file.
 *
 * The simplest case just copies the data to user
 * mode.
 */

 //读操作的描述符
typedef struct {
	size_t written;//已经拷贝到用户态缓冲区的字节数
	size_t count;//待传送的字节数
	union {
		char __user *buf;//缓冲区
		void *data;
	} arg;
	int error;//读操作错误码
} read_descriptor_t;


```

### 内存映射

1. 内存映射类型：共享型，私有型
* 共享型：在线性区页上的所有操作都会修改磁盘上的文件，对映射了同一文件的其他进程是可见的。
* 私有型：为进程读文件创建的映射，写操作不会改变文件(写时复制)，为改变的页的内容会随着磁盘的内容而更新。

### 缓存IO
1. 缓存I/O 的引入是为了减少对块设备的 I/O 操作，但是由于读写操作都先要经过缓存，然后再从缓存复制到用户空间，所以多了一次内存复制操作

![2022-05-08 19-39-43 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h218cqzwxdj30mf0hf0wy.jpg)

### 直接IO传送
1. 缓存IO传送经过中断和DMA进行,数据需要在内核缓冲和用户态进程页中互相拷贝。
2. 如果用户采用的是同步写机制（ synchronous writes ）, 那么数据会立即被写回到磁盘上，
应用程序会一直等到数据被写完为止；如果用户采用的是延迟写机制（ deferred writes ），
那么应用程序就完全不需要等到数据全部被写回到磁盘，数据只要被写到页缓存中去就可以了。
在延迟写机制的情况下，操作系统会定期地将放在页缓存中的数 据刷到磁盘上。与异步写机制
（ asynchronous writes ）不同的是，延迟写机制在数据完全写到磁盘上的时候不会通知应用
程序，而异步写机制在数据完全写到磁盘上的时候是会返回给应用程序的。所以延迟写机制本身
是存在数据丢失的风险的，而异步写机制则不会有这方面的担心
```
  
      磁盘 <----> 内核缓冲区 <----> 用户态地址空间  （两次拷贝）

```
![2022-05-07 11-38-44 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h1zouao9iqj30m50ei763.jpg)
零拷贝技术 不单只有 sendfile，如 mmap、splice 和 直接I/O 等都是 零拷贝技
2. 直接IO不经过内核缓冲区，用户态进程直接写回磁盘，这种方式性能回更高。 
3. 直接IO使用 generic_file_direct_write()函数，该函数实际调用address_space结构体注册的direct_IO()函数
4. 对于某些应用程序来说，它会有它自己的数据缓存机制，比如，它会将数据缓存
在应用程序地址空间，这类应用程序完全不需要使用操作系统内核中的 高速缓冲存储器，
这类应用程序就被称作是自缓存应用程序（ self-caching applications ）。数据库管理系统是这类应用程序的一个代表



#### glibc(POSIX AIO)版本的异步IO

1. POSIX AIO 是在用户控件模拟异步 IO 的功能，不需要内核支持，
2. 而 linux AIO 则是 linux 内核原声支持的异步 IO 调用，行为更加低级
![关于 linux IO 模型及 AIO、POSIX AIO 的简介，请参看]：https://blog.csdn.net/brucexu1978/article/details/7085924

```  
struct aio_kiocb {
	union {
		struct file		*ki_filp;
		struct kiocb		rw;
		struct fsync_iocb	fsync;
		struct poll_iocb	poll;
	};

	struct kioctx		*ki_ctx;
	kiocb_cancel_fn		*ki_cancel;

	struct io_event		ki_res;

	struct list_head	ki_list;	/* the aio core uses this
						 * for cancellation */
	refcount_t		ki_refcnt;

	/*
	 * If the aio_resfd field of the userspace iocb is not zero,
	 * this is the underlying eventfd context to deliver events to.
	 */
	struct eventfd_ctx	*ki_eventfd;
};


```

#### linux 版本的异步IO
1. 同步 IO 必须等待内核把 IO 操作处理完成后才返回。而异步 IO 不必等待 IO 操作完成，
而是向内核发起一个 IO 操作就立刻返回，当内核完成 IO 操作后，会通过信号的方式通知应用程序
2. Linux Native AIO 是 Linux 支持的原生 AIO,Linux存在很多第三方的异步 IO 库，如 libeio 和 glibc AIO
3. 第三方的异步 IO 库都不是真正的异步 IO，而是使用多线程来模拟异步 IO，如 libeio 就是使用多线程来模拟异步 IO 的
4.Linux 的异步 IO 操作主要由两个步骤组成：
* 调用 io_setup 函数创建一个一般 IO 上下文。
* 调用 io_submit 函数发起一个异步 IO 操作。
* 调用 io_getevents 函数获取异步 IO 的结果。 

```c

               io_submit()
                   |
               io_submit_one()
                   |
               __io_submit_one()


static int __io_submit_one(struct kioctx *ctx, const struct iocb *iocb,
			   struct iocb __user *user_iocb, struct aio_kiocb *req,
			   bool compat)
{
	req->ki_filp = fget(iocb->aio_fildes);
	if (unlikely(!req->ki_filp))
		return -EBADF;

	if (iocb->aio_flags & IOCB_FLAG_RESFD) {
		struct eventfd_ctx *eventfd;
		/*
		 * If the IOCB_FLAG_RESFD flag of aio_flags is set, get an
		 * instance of the file* now. The file descriptor must be
		 * an eventfd() fd, and will be signaled for each completed
		 * event using the eventfd_signal() function.
		 */
		eventfd = eventfd_ctx_fdget(iocb->aio_resfd);
		if (IS_ERR(eventfd))
			return PTR_ERR(eventfd);

		req->ki_eventfd = eventfd;
	}

	if (unlikely(put_user(KIOCB_KEY, &user_iocb->aio_key))) {
		pr_debug("EFAULT: aio_key\n");
		return -EFAULT;
	}

	req->ki_res.obj = (u64)(unsigned long)user_iocb;
	req->ki_res.data = iocb->aio_data;
	req->ki_res.res = 0;
	req->ki_res.res2 = 0;

	switch (iocb->aio_lio_opcode) {
	case IOCB_CMD_PREAD:
		return aio_read(&req->rw, iocb, false, compat);
	case IOCB_CMD_PWRITE:
		return aio_write(&req->rw, iocb, false, compat);
	case IOCB_CMD_PREADV:
		return aio_read(&req->rw, iocb, true, compat);
	case IOCB_CMD_PWRITEV:
		return aio_write(&req->rw, iocb, true, compat);
	case IOCB_CMD_FSYNC:
		return aio_fsync(&req->fsync, iocb, false);
	case IOCB_CMD_FDSYNC:
		return aio_fsync(&req->fsync, iocb, true);
	case IOCB_CMD_POLL:
		return aio_poll(req, iocb);
	default:
		pr_debug("invalid aio operation %d\n", iocb->aio_lio_opcode);
		return -EINVAL;
	}
}




//异步IO的linux系统调用。
COND_SYSCALL(io_setup);
COND_SYSCALL_COMPAT(io_setup);
COND_SYSCALL(io_destroy);
COND_SYSCALL(io_submit);
COND_SYSCALL_COMPAT(io_submit);
COND_SYSCALL(io_cancel);
COND_SYSCALL(io_getevents_time32);
COND_SYSCALL(io_getevents);
COND_SYSCALL(io_pgetevents_time32);
COND_SYSCALL(io_pgetevents);
COND_SYSCALL_COMPAT(io_pgetevents_time32);
COND_SYSCALL_COMPAT(io_pgetevents);
COND_SYSCALL(io_uring_setup);
COND_SYSCALL(io_uring_enter);
COND_SYSCALL(io_uring_register);

/***
调用io_submit后，对应于用户传递的每一个iocb结构，
会在内核态生成一个与之对应的kiocb结构，并且在
对应kioctx结构的ring_info中预留一个io_events的空间。
之后，请求的处理结果就被写到这个io_event中。

*/

//用户态的异步IO描述符
struct aio_kiocb {
	union {
		struct file		*ki_filp;
		struct kiocb		rw;
		struct fsync_iocb	fsync;
		struct poll_iocb	poll;
	};

	struct kioctx		*ki_ctx;
	kiocb_cancel_fn		*ki_cancel;

	struct io_event		ki_res;

	struct list_head	ki_list;	/* the aio core uses this
						 * for cancellation */
	refcount_t		ki_refcnt;

	/*
	 * If the aio_resfd field of the userspace iocb is not zero,
	 * this is the underlying eventfd context to deliver events to.
	 */
	struct eventfd_ctx	*ki_eventfd;
};
```
5. 要使用 Linux 原生 AIO，首先需要创建一个异步 IO 上下文，在内核中，异步 IO 上下文使用 kioctx 结构表示
6. 在 kioctx 结构中，比较重要的成员为 active_reqs 和 ring_info。active_reqs 
保存了所有正在进行的异步 IO 操作，而 ring_info 成员用于存放异步 IO 操作的结果
![2022-05-08 20-14-46 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h219ehnvkqj30we0gg41i.jpg)
```c
//句柄aio_context_t指向kioctx 异步IO上下文
//描述异步IO环境的数据结构kioctx
struct kioctx {
	struct percpu_ref	users;
	atomic_t		dead;

	struct percpu_ref	reqs;

	unsigned long		user_id;

	struct __percpu kioctx_cpu *cpu;

	/*
	 * For percpu reqs_available, number of slots we move to/from global
	 * counter at a time:
	 */
	unsigned		req_batch;
	/*
	 * This is what userspace passed to io_setup(), it's not used for
	 * anything but counting against the global max_reqs quota.
	 *
	 * The real limit is nr_events - 1, which will be larger (see
	 * aio_setup_ring())
	 */
	unsigned		max_reqs;

	/* Size of ringbuffer, in units of struct io_event */
	unsigned		nr_events;

	unsigned long		mmap_base;
	unsigned long		mmap_size;

// 环形缓冲区，内核用来写已完成的IO报告。
	struct page		**ring_pages;
	long			nr_pages;

	struct rcu_work		free_rwork;	/* see free_ioctx() */

	/*
	 * signals when all in-flight requests are done
	 */
	struct ctx_rq_wait	*rq_wait;

	struct {
		/*
		 * This counts the number of available slots in the ringbuffer,
		 * so we avoid overflowing it: it's decremented (if positive)
		 * when allocating a kiocb and incremented when the resulting
		 * io_event is pulled off the ringbuffer.
		 *
		 * We batch accesses to it with a percpu version.
		 */
		atomic_t	reqs_available;
	} ____cacheline_aligned_in_smp;

	struct {
		spinlock_t	ctx_lock;
		struct list_head active_reqs;	/* used for cancellation */
	} ____cacheline_aligned_in_smp;

	struct {
		struct mutex	ring_lock;
		wait_queue_head_t wait;
	} ____cacheline_aligned_in_smp;

	struct {
		unsigned	tail;
		unsigned	completed_events;
		spinlock_t	completion_lock;
	} ____cacheline_aligned_in_smp;

	struct page		*internal_pages[AIO_RING_PAGES];
	struct file		*aio_ring_file;

	unsigned		id;
};
```
#### 共享内存
1. 共享内存是通过将不同进程的虚拟内存地址映射到相同的物理内存地址来实现的
2. 每个共享内存都由一个名为 struct shmid_kernel 的结构体来管理，而且Linux限制了系统最大能创建的共享内存为128个

```c

struct shmid_kernel /* private to the kernel */
{
	struct kern_ipc_perm	shm_perm;
	struct file		*shm_file;
	unsigned long		shm_nattch;
	unsigned long		shm_segsz;
	time64_t		shm_atim;
	time64_t		shm_dtim;
	time64_t		shm_ctim;
	struct pid		*shm_cprid;
	struct pid		*shm_lprid;
	struct ucounts		*mlock_ucounts;

	/* The task created the shm object.  NULL if the task is dead. */
	struct task_struct	*shm_creator;
	struct list_head	shm_clist;	/* list by creator */
} __randomize_layout;

shmid_ds 结构体用于管理共享内存的信息
struct shmid_ds {
	struct ipc_perm		shm_perm;	/* operation perms */
	int			shm_segsz;	/* size of segment (bytes) */
	__kernel_old_time_t	shm_atime;	/* last attach time */
	__kernel_old_time_t	shm_dtime;	/* last detach time */
	__kernel_old_time_t	shm_ctime;	/* last change time */
	__kernel_ipc_pid_t	shm_cpid;	/* pid of creator */
	__kernel_ipc_pid_t	shm_lpid;	/* pid of last operator */
	unsigned short		shm_nattch;	/* no. of current attaches */
	unsigned short 		shm_unused;	/* compatibility */
	void 			*shm_unused2;	/* ditto - used by DIPC */
	void			*shm_unused3;	/* unused */
};
```
3. 要使用共享内存，首先需要调用 shmget()--->ksys_shmget() 函数来创建或者获取一块共享内存

```c

long ksys_shmget(key_t key, size_t size, int shmflg)
{
	struct ipc_namespace *ns;
	static const struct ipc_ops shm_ops = {//注册shm函数
		.getnew = newseg,//就是创建一个新的 struct shmid_kernel 结构体
		.associate = security_shm_associate,
		.more_checks = shm_more_checks,
	};
	struct ipc_params shm_params;

	ns = current->nsproxy->ipc_ns;

	shm_params.key = key;
	shm_params.flg = shmflg;
	shm_params.u.size = size;

	return ipcget(ns, &shm_ids(ns), &shm_ops, &shm_params);
}

SYSCALL_DEFINE3(shmget, key_t, key, size_t, size, int, shmflg)
{
	return ksys_shmget(key, size, shmflg);
}
```

4. shmat() 函数用于将共享内存映射到本地虚拟内存地址
```c

#define SHM_PATH "/tmp/shm"
#define SHM_SIZE 128

int main(int argc, char* argv[]){
  int shmid;
  char* addr;
 /*系统建立IPC通讯（如消息队列、共享内存时）必须指定一个ID值 。通常情况下，该id值通过ftok函数得到 。  
   key_t ftok( char * fname, int id )
   参数说明：
        fname就时您指定的文档名
        id是子序号。
  */
  key_t key = ftok(SHM_PATH, 0x6666);
  
  /*
   * 得到一个共享内存标识符或创建一个共享内存对象并返回共享内存标识符
   *int shmget( key_t, size_t, flag);
   * */
  shmid = shmget(key, SHM_SIZE, IPC_CREAT|IPC_EXCL|0666);
  if(shmid < 0){
    printf("failed to create a share memory object\n");
    return -1;
  }

  /**
   *shmat（）是用来允许本进程访问一块共享内存的函数，与shmget（）函数共同使用。
   *shmat的原型是：void *shmat（int shmid，const void *shmaddr,int shmflg）;
   * 如果 shmaddr 是NULL，系统将自动选择一个合适的地址！ 如果shmaddr不是NULL 并且没有指定SHM_RND 则此段连接到addr所指定的地址上 
   * shmat返回值是该段所连接的实际地址 如果出错返回-1
   * */
   addr = shmat(shmid, NULL, 0);
   if(addr <= 0){
     printf("failed to map share memory\n");
     return -1;
   }
   /*向addr指定的地址写入内容(字符)，不包括字符串结束符*/
   sprintf(addr, "%s", "hello world!\n");

   return 0;
}



SYSCALL_DEFINE3(shmat, int, shmid, char __user *, shmaddr, int, shmflg)
{
	unsigned long ret;
	long err;
  /*
    do_shmat()会调用do_mmap()获取一个vm_area_struct结构体，然后返回一个虚拟地址的addr，
    物理空间的分配在缺页异常的时候会分配
  **/
	err = do_shmat(shmid, shmaddr, shmflg, &ret, SHMLBA);
	if (err)
		return err;
	force_successful_syscall_return();
	return (long)ret;
}

```

#### 页缓存
1. page_cache_alloc()分配一个即将加入页缓存的页
2. add_to_page_cache_lru()将页插入到页缓存中。
3. find_get_page()判断页是否已经加入页缓存
4. mpage_readpage(), mpage_writepage()对整页进行操作。

#### 块缓存
1. 可以使用缓冲区buffer_head，把一个整页换分为几个叫较小的单位，这样只需把修改的buffer_head写回磁盘即可
提高文件的读写性能。
```c
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

```

2. page的private属性用来关联缓冲区和页(private指向划分更小单位的第一个缓冲头buffer_head)
各个缓冲头buffer_head的b_this_page连接起来形成一个环形链表
```c
struct page {

................

unsigned long private;

.................

}

//该函数根据页的大小建立一个环形buffer_head,并将其与page联系起来。这样从page就可以扫描与页关联的所有buffer_head实例
void create_empty_buffers(struct page *page,
			unsigned long blocksize, unsigned long b_state)
{
	struct buffer_head *bh, *head, *tail;

	head = alloc_page_buffers(page, blocksize, true);
	bh = head;
	do {
		bh->b_state |= b_state;
		tail = bh;
		bh = bh->b_this_page;
	} while (bh);
	tail->b_this_page = head;

	spin_lock(&page->mapping->private_lock);
	if (PageUptodate(page) || PageDirty(page)) {
		bh = head;
		do {
			if (PageDirty(page))
				set_buffer_dirty(bh);
			if (PageUptodate(page))
				set_buffer_uptodate(bh);
			bh = bh->b_this_page;
		} while (bh != head);
	}
	attach_page_private(page, head);
	spin_unlock(&page->mapping->private_lock);
}
EXPORT_SYMBOL(create_empty_buffers);

```

#### LRU缓存(独立的缓冲区)
1. LRU缓存很小，只有16和buffer_head元素，
2.__getblk_gfg()函数来对缓冲区进行查找，先查找LRU缓存，然后查找页缓存，不成功则调用grow_buffers()函数为缓冲头和数据分配内存。

```c


#define BH_LRU_SIZE	16
//是per-cpu元素，改善cpu高速缓存的使用效率
struct bh_lru {
	struct buffer_head *bhs[BH_LRU_SIZE];//缓冲头指针数组
};
```




