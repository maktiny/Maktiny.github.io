# 进程通信
1. 管道
2. 信号量
3. 消息队列
4. 共享内存
5. 套接字

### ![20170519181341767.png](http://tva1.sinaimg.cn/large/0070vHShgy1gvvcs4fjd3j30gm06i77b.jpg)
## pipe_inode_info
1. 管道注册成pipefs特殊文件系统，每个管道，内核都要创建
一个索引节点，两个文件对象(读和写)
```c


struct pipe_inode_info {
	struct mutex mutex;
	wait_queue_head_t rd_wait, wr_wait;
	unsigned int head;
	unsigned int tail;
	unsigned int max_usage;
	unsigned int ring_size;
#ifdef CONFIG_WATCH_QUEUE
	bool note_loss;
#endif
	unsigned int nr_accounted;
	unsigned int readers;
	unsigned int writers;
	unsigned int files;
	unsigned int r_counter;
	unsigned int w_counter;
	unsigned int poll_usage;
	struct page *tmp_page;
	struct fasync_struct *fasync_readers;
	struct fasync_struct *fasync_writers;
	struct pipe_buffer *bufs;//最大16个页
	struct user_struct *user;
#ifdef CONFIG_WATCH_QUEUE
	struct watch_queue *watch_queue;
#endif
};
```

2. 管道缓冲区：数组pipe_buffer[16] （16个页）
```c


struct pipe_buffer {
	struct page *page;
	unsigned int offset, len;
	const struct pipe_buf_operations *ops;
	unsigned int flags;
	unsigned long private;
};

```

3. 父进程创建的管道，子进程也可以读写
4. 管道是一种特殊的文件系统
```c


static struct file_system_type pipe_fs_type = {
	.name		= "pipefs",
	.init_fs_context = pipefs_init_fs_context,
	.kill_sb	= kill_anon_super,
};

static int __init init_pipe_fs(void)
{
	int err = register_filesystem(&pipe_fs_type);

	if (!err) {
		pipe_mnt = kern_mount(&pipe_fs_type);
		if (IS_ERR(pipe_mnt)) {
			err = PTR_ERR(pipe_mnt);
			unregister_filesystem(&pipe_fs_type);
		}
	}
	return err;
}
```

### 创建和撤销管道
```c
                sys_pipe()系统调用
                  |
                  ---do_pipe2() 系统函数
                       |
                       ---__do_pipe_flags() 
                              |
                              |
                      ______________________________
                      |                            |
              create_pipe_files()                 get_unused_fd_flages()#获取文件描述符
                    |//创建管道所需的两个文件
                    --——get_pipe_inode()
                    #分配索引节点，并初始化pip_inode_info



static int do_pipe2(int __user *fildes, int flags)
{
	struct file *files[2];
	int fd[2];
	int error;

	error = __do_pipe_flags(fd, files, flags);
	if (!error) {
		if (unlikely(copy_to_user(fildes, fd, sizeof(fd)))) {
			fput(files[0]);
			fput(files[1]);
			put_unused_fd(fd[0]);
			put_unused_fd(fd[1]);
			error = -EFAULT;
		} else {
			fd_install(fd[0], files[0]);
			fd_install(fd[1], files[1]);
		}
	}
	return error;
}

SYSCALL_DEFINE2(pipe2, int __user *, fildes, int, flags)
{
	return do_pipe2(fildes, flags);
}

SYSCALL_DEFINE1(pipe, int __user *, fildes)
{
	return do_pipe2(fildes, 0);
}


static int __do_pipe_flags(int *fd, struct file **files, int flags)
{
	int error;
	int fdw, fdr;

	if (flags & ~(O_CLOEXEC | O_NONBLOCK | O_DIRECT | O_NOTIFICATION_PIPE))
		return -EINVAL;

	error = create_pipe_files(files, flags);
	if (error)
		return error;

	error = get_unused_fd_flags(flags);
	if (error < 0)
		goto err_read_pipe;
	fdr = error;

	error = get_unused_fd_flags(flags);
	if (error < 0)
		goto err_fdr;
	fdw = error;

	audit_fd_pair(fdr, fdw);
	fd[0] = fdr;
	fd[1] = fdw;
	return 0;

 err_fdr:
	put_unused_fd(fdr);
 err_read_pipe:
	fput(files[0]);
	fput(files[1]);
	return error;
}



pipe_release()撤销管道
```

### 管道读/写数据
```c

匿名管道和命名管道区别就在于匿名管道会通过dup2()指定输入输出源，完成之后立即释放，
而命名管道通过mkfifo创建挂载后，需要手动调用pipe_read()和pipe_write()来完成其功能，表现到用户端即为前面提到的例子。

pipe_write()

pipe_read()
```

## System V IPC （进程间的通信机制）
1. IPC资源包括(信号量， 消息对列， 共享内存)，资源持久永久驻留内存,
可以被换出，除非进程释放。
2. IPC资源可以由任一进程使用，即使父进程不一样。IPC标识符唯一。
```c

struct ipc_namespace {
	struct ipc_ids	ids[3];----
.........................         |
};                                | //表示信号量，消息队列，共享内存三种IPC
#define IPC_SEM_IDS	0 //信号量
#define IPC_MSG_IDS	1 //消息队列
#define IPC_SHM_IDS	2 //共享内存


/*获取ipc_ids */
#define sem_ids(ns)	((ns)->ids[IPC_SEM_IDS])
#define shm_ids(ns)	((ns)->ids[IPC_SHM_IDS])
#define msg_ids(ns)	((ns)->ids[IPC_MSG_IDS])

struct ipc_ids {
	int in_use;//表示当前种类的IPC使用的数量
	unsigned short seq;// seq 和 next_id 用于一起生成 IPC 唯一的 id
	struct rw_semaphore rwsem;
	struct idr ipcs_idr;//基数树用于快速查找IPC
	int max_idx;
	int last_idx;	/* For wrap around detection */
#ifdef CONFIG_CHECKPOINT_RESTORE
	int next_id;
#endif
	struct rhashtable key_ht;
};


struct idr {
	struct radix_tree_root	idr_rt;//基数树进行管理
	unsigned int		idr_base;
	unsigned int		idr_next;
};

```
### 消息队列， 信号量，共享内存的封装
```c
struct kern_ipc_perm {
	spinlock_t	lock;
	bool		deleted;
	int		id;
	key_t		key;
	kuid_t		uid;
	kgid_t		gid;
	kuid_t		cuid;
	kgid_t		cgid;
	umode_t		mode;
	unsigned long	seq;
	void		*security;

	struct rhash_head khtnode;

	struct rcu_head rcu;
	refcount_t refcount;
}

struct sem_array {
    struct kern_ipc_perm  sem_perm;  /* permissions .. see ipc.h */
......
} __randomize_layout;

struct msg_queue {
    struct kern_ipc_perm q_perm;
......
} __randomize_layout;

struct shmid_kernel /* private to the kernel */
{  
    struct kern_ipc_perm  shm_perm;
......
} __randomize_layout;


static inline struct sem_array *sem_obtain_object(struct ipc_namespace *ns, int id)
{
	struct kern_ipc_perm *ipcp = ipc_obtain_object_idr(&sem_ids(ns), id);

	if (IS_ERR(ipcp))
		return ERR_CAST(ipcp);

	return container_of(ipcp, struct sem_array, sem_perm);
}

static inline struct msg_queue *msq_obtain_object(struct ipc_namespace *ns, int id)
{
	struct kern_ipc_perm *ipcp = ipc_obtain_object_idr(&msg_ids(ns), id);

	if (IS_ERR(ipcp))
		return ERR_CAST(ipcp);

	return container_of(ipcp, struct msg_queue, q_perm);
}

static inline struct shmid_kernel *shm_obtain_object(struct ipc_namespace *ns, int id)
{
	struct kern_ipc_perm *ipcp = ipc_obtain_object_idr(&shm_ids(ns), id);

	if (IS_ERR(ipcp))
		return ERR_CAST(ipcp);

	return container_of(ipcp, struct shmid_kernel, shm_perm);
}
```




### 创建共享内存
1. 共享内存的创建通过shmget()实现
```c

long ksys_shmget(key_t key, size_t size, int shmflg)
{
	struct ipc_namespace *ns;
	static const struct ipc_ops shm_ops = {
		.getnew = newseg,//新建共享内存的函数
		.associate = security_shm_associate,
		.more_checks = shm_more_checks,
	};
	struct ipc_params shm_params;

	ns = current->nsproxy->ipc_ns; 线程所属的ipc_namespace结构体

	shm_params.key = key;
	shm_params.flg = shmflg;
	shm_params.u.size = size;
/*ipcget()会根据传参key的类型是否是IPC_PRIVATE选择调用ipcget_new()创建或者调用ipcget_public()打开对应的共享内存*/
	return ipcget(ns, &shm_ids(ns), &shm_ops, &shm_params);
}

SYSCALL_DEFINE3(shmget, key_t, key, size_t, size, int, shmflg)
{
	return ksys_shmget(key, size, shmflg);
}

int ipcget(struct ipc_namespace *ns, struct ipc_ids *ids,
			const struct ipc_ops *ops, struct ipc_params *params)
{
	if (params->key == IPC_PRIVATE)
		return ipcget_new(ns, ids, ops, params);//调用ksys_shmget()注册的ipc_ops 的newseg函数创建新的共享内存
	else
		return ipcget_public(ns, ids, ops, params);//ipc_findkey()查找基数树，查找kern_ipc_perm，(如果设置IPC_PRIVATE)找不到就调用getnew()创建新的共享内存
}
```
### 共享内存的映射
1. 共享内存的映射通过shmat()实现
```c

SYSCALL_DEFINE3(shmat, int, shmid, char __user *, shmaddr, int, shmflg)
{
	unsigned long ret;
	long err;

	err = do_shmat(shmid, shmaddr, shmflg, &ret, SHMLBA);
	if (err)
		return err;
	force_successful_syscall_return();
	return (long)ret;
}
```

### 信号量的创建
1. 信号量的创建和共享内存的创建一样

```c
long ksys_semget(key_t key, int nsems, int semflg)
{
	struct ipc_namespace *ns;

        /*
          共享内存最终走到newseg()函数，而信号量则调用newary()，该函数也有着类似的逻辑：
通过kvmalloc()在直接映射区分配struct sem_array结构体描述该信号量。在该结构体中会有多个信号量保存在struct sem sems[]中，通过semval表示当前信号量。
初始化sem_array和sems中的各个链表
        */
	static const struct ipc_ops sem_ops = {
		.getnew = newary,
		.associate = security_sem_associate,
		.more_checks = sem_more_checks,
	};
	struct ipc_params sem_params;

	ns = current->nsproxy->ipc_ns;

	if (nsems < 0 || nsems > ns->sc_semmsl)
		return -EINVAL;

	sem_params.key = key;
	sem_params.flg = semflg;
	sem_params.u.nsems = nsems;

	return ipcget(ns, &sem_ids(ns), &sem_ops, &sem_params);
}

SYSCALL_DEFINE3(semget, key_t, key, int, nsems, int, semflg)
{
	return ksys_semget(key, nsems, semflg);
}

```
### 信号量的初始化
1. 信号量通过semctl()实现初始化，主要使用semctl_main()和semctl_setval()函数。
```c
SYSCALL_DEFINE4(semctl, int, semid, int, semnum, int, cmd, unsigned long, arg)
{
	return ksys_semctl(semid, semnum, cmd, arg, IPC_64);
}

```
### 信号量的操作
1. 
```c
SYSCALL_DEFINE3(semop, int, semid, struct sembuf __user *, tsops,
		unsigned, nsops)
{
	return do_semtimedop(semid, tsops, nsops, NULL);
}

```

### 信号量的 sem_undo 机制
1. 信号量是整个 Linux 可见的全局资源，而不是某个进程独占的资源，好处是可以跨进程通信，坏处就是如果一个进程通过操作拿到了一个信号量，
但是不幸异常退出了，如果没有来得及归还这个信号量，可能所有其他的进程都阻塞了。为此，Linux设计了SEM_UNDO机制解决该问题。该机制简而言之
就是每一个 semop 操作都会保存一个反向 struct sem_undo 操作，当因为某个进程异常退出的时候，这个进程做的所有的操作都会回退，
从而保证其他进程可以正常工作。在sem_flg标记位设置SUM_UNDO即可开启该功能
```c

struct task_struct {
..........................


#ifdef CONFIG_SYSVIPC
	struct sysv_sem			sysvsem;
	struct sysv_shm			sysvshm;
#endif

...........................
}

struct sysv_sem {
	struct sem_undo_list *undo_list;//每个进程的undo列表
};


/* One queue for each sleeping process in the system. */
struct sem_queue {
	struct list_head	list;	 /* queue of pending operations */
	struct task_struct	*sleeper; /* this process */
	struct sem_undo		*undo;	 /* undo structure */
	struct pid		*pid;	 /* process id of requesting process */
	int			status;	 /* completion status of operation */
	struct sembuf		*sops;	 /* array of pending operations */
	struct sembuf		*blocking; /* the operation that blocked */
	int			nsops;	 /* number of operations */
	bool			alter;	 /* does *sops alter the array? */
	bool                    dupsop;	 /* sops on more than one sem_num */
};

struct sem_undo {
	struct list_head	list_proc;	/* per-process list: *
						 * all undos from one process
						 * rcu protected */
	struct rcu_head		rcu;		/* rcu struct for sem_undo */
	struct sem_undo_list	*ulp;		/* back ptr to sem_undo_list */
	struct list_head	list_id;	/* per semaphore array list:
						 * all undos for one array */
	int			semid;		/* semaphore set identifier */
	short			*semadj;	/* array of adjustments */
						/* one per semaphore */
};

struct sem_undo_list {
	refcount_t		refcnt;
	spinlock_t		lock;
	struct list_head	list_proc;
};

```

## 消息队列(链表实现)
1. 消息队列，消息被读出之后，就删除
2. 消息队列数缺省16,每个大小8192B
```c
/*创建消息队列*/
SYSCALL_DEFINE2(msgget, key_t, key, int, msgflg)
{
	return ksys_msgget(key, msgflg);
}

/*消息队列的初始化*/
SYSCALL_DEFINE3(msgctl, int, msqid, int, cmd, struct msqid_ds __user *, buf)
{
	return ksys_msgctl(msqid, cmd, buf, IPC_64);
}

/*发送消息*/
SYSCALL_DEFINE4(msgsnd, int, msqid, struct msgbuf __user *, msgp, size_t, msgsz,
		int, msgflg)
{
	return ksys_msgsnd(msqid, msgp, msgsz, msgflg);
}

/*接收消息*/
SYSCALL_DEFINE5(msgrcv, int, msqid, struct msgbuf __user *, msgp, size_t, msgsz,
		long, msgtyp, int, msgflg)
{
	return ksys_msgrcv(msqid, msgp, msgsz, msgtyp, msgflg);
}

```

## 套接字socket
1. 
```c
   +----------------------+
   +      应用层          +
   +      表示层          +
   +      会话层          +
   +      传输层          +
   +      网络层          +
   +     数据链路层       +
   +      物理层          +
   +----------------------+
          

struct socket {   //传输层套接字
	socket_state		state;

	short			type;

	unsigned long		flags;

	struct file		*file;
	struct sock		*sk; //网络层的套接字数据结构
	const struct proto_ops	*ops;//socket的操作函数指针：bind(), accept()等

	struct socket_wq	wq;//socket的等待队列
};


typedef enum {
	SS_FREE = 0,			/* not allocated		*/
	SS_UNCONNECTED,			/* unconnected to any socket	*/
	SS_CONNECTING,			/* in process of connecting	*/
	SS_CONNECTED,			/* connected to socket		*/
	SS_DISCONNECTING		/* in process of disconnecting	*/
} socket_state;



//sk_buff则是该网络连接对应的数据包的存储
//sk_buff构成双向链表用于管理全部的sk_buff。

```

### 套接字socket的创建
1. 通过socket()生成套接字，其系统调用如下，主要调用sock_create()创建结构体socket，并通过sock_map_fd()将其和文件描述符进行绑定
2. 参数类型
* family：表示使用什么 IP 层协议。AF_INET 表示 IPv4，AF_INET6 表示 IPv6。这里需要注意的是，我们会常见到AF_INET, AF_PACKET，AF_UNIX等，
          AF_UNIX用于主机内进程间通信，AF_INET和AF_PACKET的区别在于前者只能看到IP层以上，而后者可以看到链路层信息，即作用域不同。
* type：表示 socket 类型。SOCK_STREAM 是面向数据流的，协议 IPPROTO_TCP 属于这种类型。SOCK_DGRAM 是面向数据报的，
        协议 IPPROTO_UDP 属于这种类型。如果在内核里面看的话，IPPROTO_ICMP 也属于这种类型。SOCK_RAW 是原始的 IP 包，IPPROTO_IP 属于这种类型。
* protocol： 表示的协议，包括 IPPROTO_TCP、IPPTOTO_UDP
```c
int __sys_socket(int family, int type, int protocol)
{
	int retval;
	struct socket *sock;
	int flags;

	/* Check the SOCK_* constants for consistency.  */
	BUILD_BUG_ON(SOCK_CLOEXEC != O_CLOEXEC);
	BUILD_BUG_ON((SOCK_MAX | SOCK_TYPE_MASK) != SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_CLOEXEC & SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_NONBLOCK & SOCK_TYPE_MASK);

	flags = type & ~SOCK_TYPE_MASK;
	if (flags & ~(SOCK_CLOEXEC | SOCK_NONBLOCK))
		return -EINVAL;
	type &= SOCK_TYPE_MASK;

	if (SOCK_NONBLOCK != O_NONBLOCK && (flags & SOCK_NONBLOCK))
		flags = (flags & ~SOCK_NONBLOCK) | O_NONBLOCK;

	retval = sock_create(family, type, protocol, &sock);
	if (retval < 0)
		return retval;

	return sock_map_fd(sock, flags & (O_CLOEXEC | O_NONBLOCK));
}

SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)
{
	return __sys_socket(family, type, protocol);
}
    //ipv4/af_inet.c
static const struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,//用于socket系统调用的创建,在__sock_create()中调用
	.owner	= THIS_MODULE,
};
```

3. sock_create()调用__sock_create()。这里首先调用sock_alloc()分配套接字结构体sock并赋值类型为type，接着调用对应的create()函数按照protocol对sock进行填充。


```c

int __sock_create(struct net *net, int family, int type, int protocol,
			 struct socket **res, int kern)
{
	int err;
	struct socket *sock;
	const struct net_proto_family *pf;

	/*
	 *      Check protocol is in range
	 */
	if (family < 0 || family >= NPROTO)
		return -EAFNOSUPPORT;
	if (type < 0 || type >= SOCK_MAX)
		return -EINVAL;

	/* Compatibility.

	   This uglymoron is moved from INET layer to here to avoid
	   deadlock in module load.
	 */
	if (family == PF_INET && type == SOCK_PACKET) {
		pr_info_once("%s uses obsolete (PF_INET,SOCK_PACKET)\n",
			     current->comm);
		family = PF_PACKET;
	}

	err = security_socket_create(family, type, protocol, kern);
	if (err)
		return err;

	/*
	 *	Allocate the socket and allow the family to set things up. if
	 *	the protocol is 0, the family is instructed to select an appropriate
	 *	default.
	 */
	sock = sock_alloc();
	if (!sock) {
		net_warn_ratelimited("socket: no more sockets\n");
		return -ENFILE;	/* Not exactly a match, but its the
				   closest posix thing */
	}

	sock->type = type;

#ifdef CONFIG_MODULES
	/* Attempt to load a protocol module if the find failed.
	 *
	 * 12/09/1996 Marcin: But! this makes REALLY only sense, if the user
	 * requested real, full-featured networking support upon configuration.
	 * Otherwise module support will break!
	 */
	if (rcu_access_pointer(net_families[family]) == NULL)
		request_module("net-pf-%d", family);
#endif

	rcu_read_lock();
	pf = rcu_dereference(net_families[family]);
	err = -EAFNOSUPPORT;
	if (!pf)
		goto out_release;

	/*
	 * We will call the ->create function, that possibly is in a loadable
	 * module, so we have to bump that loadable module refcnt first.
	 */
	if (!try_module_get(pf->owner))
		goto out_release;

	/* Now protected by module ref count */
	rcu_read_unlock();

	err = pf->create(net, sock, protocol, kern); //真正创建socket的函数，就是通过net_proto_family结构体注册的函数指针
	if (err < 0)
		goto out_module_put;

	/*
	 * Now to bump the refcnt of the [loadable] module that owns this
	 * socket at sock_release time we decrement its refcnt.
	 */
	if (!try_module_get(sock->ops->owner))
		goto out_module_busy;

	/*
	 * Now that we're done with the ->create function, the [loadable]
	 * module can have its refcnt decremented
	 */
	module_put(pf->owner);
	err = security_socket_post_create(sock, family, type, protocol, kern);
	if (err)
		goto out_sock_release;
	*res = sock;

	return 0;

out_module_busy:
	err = -EAFNOSUPPORT;
out_module_put:
	sock->ops = NULL;
	module_put(pf->owner);
out_sock_release:
	sock_release(sock);
	return err;

out_release:
	rcu_read_unlock();
	goto out_sock_release;
}
EXPORT_SYMBOL(__sock_create);




/*真正创建socket的函数，就是通过net_proto_family结构体注册的函数指针*/
static int inet_create(struct net *net, struct socket *sock, int protocol,
		       int kern)
{
	struct sock *sk;
	struct inet_protosw *answer;
	struct inet_sock *inet;
	struct proto *answer_prot;
	unsigned char answer_flags;
	int try_loading_module = 0;
	int err;

	if (protocol < 0 || protocol >= IPPROTO_MAX)
		return -EINVAL;

	sock->state = SS_UNCONNECTED;

	/* Look for the requested type/protocol pair. */
lookup_protocol:
	err = -ESOCKTNOSUPPORT;
	rcu_read_lock();
	list_for_each_entry_rcu(answer, &inetsw[sock->type], list) { // inetsw[]数组中包含各种传输层协议

		err = 0;
		/* Check the non-wild match. */
		if (protocol == answer->protocol) {
			if (protocol != IPPROTO_IP)
				break;
		} else {
			/* Check for the two wild cases. */
			if (IPPROTO_IP == protocol) {
				protocol = answer->protocol;
				break;
			}
			if (IPPROTO_IP == answer->protocol)
				break;
		}
		err = -EPROTONOSUPPORT;
	}

	if (unlikely(err)) {
		if (try_loading_module < 2) {
			rcu_read_unlock();
			/*
			 * Be more specific, e.g. net-pf-2-proto-132-type-1
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP-type-SOCK_STREAM)
			 */
			if (++try_loading_module == 1)
				request_module("net-pf-%d-proto-%d-type-%d",
					       PF_INET, protocol, sock->type);
			/*
			 * Fall back to generic, e.g. net-pf-2-proto-132
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP)
			 */
			else
				request_module("net-pf-%d-proto-%d",
					       PF_INET, protocol);
			goto lookup_protocol;
		} else
			goto out_rcu_unlock;
	}

	err = -EPERM;
	if (sock->type == SOCK_RAW && !kern &&
	    !ns_capable(net->user_ns, CAP_NET_RAW))
		goto out_rcu_unlock;
/*struct socket *sock 的 ops 成员变量被赋值为 answer 的 ops。对于 TCP 来讲，就是 inet_stream_ops。后面任何用户对于这个 socket 的操作都是通过 inet_stream_ops 进行的。*/
	sock->ops = answer->ops;
	answer_prot = answer->prot;
	answer_flags = answer->flags;
	rcu_read_unlock();

	WARN_ON(!answer_prot->slab);
/*调用sk_alloc()创建一个 网络层struct sock *sk 对象并赋值
调用inet_sk()创建一个 struct inet_sock 结构并赋值。上文已说明INET作用域，而inet_sock即是对sock的INET形式封装，在sock的基础上增加了很多新的特性*/
	err = -ENOMEM;
	sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot, kern);
	if (!sk)
		goto out;

	err = 0;
	if (INET_PROTOSW_REUSE & answer_flags)
		sk->sk_reuse = SK_CAN_REUSE;

	inet = inet_sk(sk);
	inet->is_icsk = (INET_PROTOSW_ICSK & answer_flags) != 0;

	inet->nodefrag = 0;

	if (SOCK_RAW == sock->type) {
		inet->inet_num = protocol;
		if (IPPROTO_RAW == protocol)
			inet->hdrincl = 1;
	}

	if (net->ipv4.sysctl_ip_no_pmtu_disc)
		inet->pmtudisc = IP_PMTUDISC_DONT;
	else
		inet->pmtudisc = IP_PMTUDISC_WANT;

	inet->inet_id = 0;

	sock_init_data(sock, sk);

	sk->sk_destruct	   = inet_sock_destruct;
	sk->sk_protocol	   = protocol;
	sk->sk_backlog_rcv = sk->sk_prot->backlog_rcv;

	inet->uc_ttl	= -1;
	inet->mc_loop	= 1;
	inet->mc_ttl	= 1;
	inet->mc_all	= 1;
	inet->mc_index	= 0;
	inet->mc_list	= NULL;
	inet->rcv_tos	= 0;

	sk_refcnt_debug_inc(sk);

	if (inet->inet_num) {
		/* It assumes that any protocol which allows
		 * the user to assign a number at socket
		 * creation time automatically
		 * shares.
		 */
		inet->inet_sport = htons(inet->inet_num);
		/* Add to protocol hash chains. */
		err = sk->sk_prot->hash(sk);
		if (err) {
			sk_common_release(sk);
			goto out;
		}
	}

	if (sk->sk_prot->init) {
		err = sk->sk_prot->init(sk);
		if (err) {
			sk_common_release(sk);
			goto out;
		}
	}

	if (!kern) {
		err = BPF_CGROUP_RUN_PROG_INET_SOCK(sk);
		if (err) {
			sk_common_release(sk);
			goto out;
		}
	}
out:
	return err;
out_rcu_unlock:
	rcu_read_unlock();
	goto out;
}

```

4. sock_alloc()中我们看到了熟悉的东西：new_inode_pseudo()，即依照着虚拟文件系统的方式为套接字生成inode，接着通过SOCKET_I()获取其对应的socket，再进行填充

```c

struct socket *sock_alloc(void)
{
	struct inode *inode;
	struct socket *sock;

	inode = new_inode_pseudo(sock_mnt->mnt_sb);
	if (!inode)
		return NULL;

	sock = SOCKET_I(inode);

	inode->i_ino = get_next_ino();
	inode->i_mode = S_IFSOCK | S_IRWXUGO;
	inode->i_uid = current_fsuid();
	inode->i_gid = current_fsgid();
	inode->i_op = &sockfs_inode_ops;

	return sock;
}
EXPORT_SYMBOL(sock_alloc);

struct socket_alloc {
	struct socket socket;
	struct inode vfs_inode;
};

static inline struct socket *SOCKET_I(struct inode *inode)
{
	return &container_of(inode, struct socket_alloc, vfs_inode)->socket;
}
```

5. inetsw数组里面的内容是 struct inet_protosw，对于每个类型的协议均有一项，
这一项里面是属于这个类型的协议。inetsw 数组是在系统初始化的时候初始化的，一个
循环会将 inetsw 数组的每一项都初始化为一个链表。接下来一个循环将 inetsw_array 注册到 inetsw 数组里面去。
```c

static struct list_head inetsw[SOCK_MAX];


static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},

	{
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_UDP,
		.prot =       &udp_prot,
		.ops =        &inet_dgram_ops,
		.flags =      INET_PROTOSW_PERMANENT,
       },

       {
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_ICMP,
		.prot =       &ping_prot,
		.ops =        &inet_sockraw_ops,
		.flags =      INET_PROTOSW_REUSE,
       },

       {
	       .type =       SOCK_RAW,
	       .protocol =   IPPROTO_IP,	/* wild card */
	       .prot =       &raw_prot,
	       .ops =        &inet_sockraw_ops,
	       .flags =      INET_PROTOSW_REUSE,
       }
};

static int __init inet_init(void)
{
	struct inet_protosw *q;
	struct list_head *r;
	int rc;

	sock_skb_cb_check_size(sizeof(struct inet_skb_parm));

	rc = proto_register(&tcp_prot, 1);
	if (rc)
		goto out;

	rc = proto_register(&udp_prot, 1);
	if (rc)
		goto out_unregister_tcp_proto;

	rc = proto_register(&raw_prot, 1);
	if (rc)
		goto out_unregister_udp_proto;

	rc = proto_register(&ping_prot, 1);
	if (rc)
		goto out_unregister_raw_proto;

	/*
	 *	Tell SOCKET that we are alive...
	 */

	(void)sock_register(&inet_family_ops);

#ifdef CONFIG_SYSCTL
	ip_static_sysctl_init();
#endif

	/*
	 *	Add all the base protocols.
	 */

	if (inet_add_protocol(&icmp_protocol, IPPROTO_ICMP) < 0)
		pr_crit("%s: Cannot add ICMP protocol\n", __func__);
	if (inet_add_protocol(&udp_protocol, IPPROTO_UDP) < 0)
		pr_crit("%s: Cannot add UDP protocol\n", __func__);
	if (inet_add_protocol(&tcp_protocol, IPPROTO_TCP) < 0)
		pr_crit("%s: Cannot add TCP protocol\n", __func__);
#ifdef CONFIG_IP_MULTICAST
	if (inet_add_protocol(&igmp_protocol, IPPROTO_IGMP) < 0)
		pr_crit("%s: Cannot add IGMP protocol\n", __func__);
#endif

	/* Register the socket-side information for inet_create. */
	for (r = &inetsw[0]; r < &inetsw[SOCK_MAX]; ++r)
		INIT_LIST_HEAD(r); //把inetsw[]数组中的元素初始化成链表

	for (q = inetsw_array; q < &inetsw_array[INETSW_ARRAY_LEN]; ++q)
		inet_register_protosw(q);

	/*
	 *	Set the ARP module up
	 */

	arp_init();

	/*
	 *	Set the IP module up
	 */

	ip_init();

	/* Setup TCP slab cache for open requests. */
	tcp_init();

	/* Setup UDP memory threshold */
	udp_init();

	/* Add UDP-Lite (RFC 3828) */
	udplite4_register();

	raw_init();

	ping_init();

	/*
	 *	Set the ICMP layer up
	 */

	if (icmp_init() < 0)
		panic("Failed to create the ICMP control socket.\n");

	/*
	 *	Initialise the multicast router
	 */
#if defined(CONFIG_IP_MROUTE)
	if (ip_mr_init())
		pr_crit("%s: Cannot init ipv4 mroute\n", __func__);
#endif

	if (init_inet_pernet_ops())
		pr_crit("%s: Cannot init ipv4 inet pernet ops\n", __func__);
	/*
	 *	Initialise per-cpu ipv4 mibs
	 */

	if (init_ipv4_mibs())
		pr_crit("%s: Cannot init ipv4 mibs\n", __func__);

	ipv4_proc_init();

	ipfrag_init();

	dev_add_pack(&ip_packet_type);

	ip_tunnel_core_init();

	rc = 0;
out:
	return rc;
out_unregister_raw_proto:
	proto_unregister(&raw_prot);
out_unregister_udp_proto:
	proto_unregister(&udp_prot);
out_unregister_tcp_proto:
	proto_unregister(&tcp_prot);
	goto out;
}

fs_initcall(inet_init);

```

#### socket发送信息
```c
//TO DO: 网络协议栈

```



#### socket接收信息

