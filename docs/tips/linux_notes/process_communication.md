# 进程通信
1. 管道和FIFO
2. 信号量
3. 消息队列
4. 共享内存
5. 套接字

### ![20170519181341767.png](http://tva1.sinaimg.cn/large/0070vHShgy1gvvcs4fjd3j30gm06i77b.jpg)
## pipe_inode_info
1. 管道注册成pipefs特殊文件系统，每个管道，内核都要创建
一个索引节点，两个文件对象(读和写)
2. 管道缓冲区：数组pipe_buffer[16] （16个页）
3. 父进程创建的管道，子进程也可以读写

### 创建和撤销管道
```
                sys_pipe()系统调用
                  |
                  ---do_pipe2() 系统函数
                       |
                       ---__do_pipe_flags() 
                              |
                              |
                      ______________________________
                      |                            |
              create_pipe_files()                 get_unuserd_fd_flages()#获取文件描述符
                    |
                    --——get_pipe_inode()
                    #分配索引节点，并初始化pip_inode_info

pipe_release()撤销管道
```

### 管道写数据
```
pip_write()

```
### 管道读数据
```
pipe_read()

```

## FIFO
FIFO与管道的区别：
1. FIFO的索引节点注册在系统目录树上，而不是特殊文件系统
2. FIFO是一种双向通信管道，可以以读写模式打开一个FIFO

### 创建和撤销FIFO
```
do_sys_mknod()系统调用创建
```
# System V IPC （进程间的通信机制）
1. IPC资源包括(信号量， 消息对列， 共享内存)，资源持久永久驻留内存,
可以被换出，除非进程释放。
2. IPC资源可以由任一进程使用，即使父进程不一样。IPC标识符唯一。
```      
    信号量，
long ksys_semget(key_t key, int nsems, int semflg)
               |
      int ipcget(struct ipc_namespace *ns, struct ipc_ids *ids,
			const struct ipc_ops *ops, struct ipc_params *params)


消息队列 ksys_msgget()
共享内存 ksys_shmget() 都一样调用ipcget()，
返回与关键字绑定的IPC标识符。
```

## 消息队列(链表实现)
1. 消息队列，消息被读出之后，就删除
2. 消息队列数缺省16,每个大小8192B
```
msgsnd()  #发送消息
msgrcv()  #接受消息
```

## 共享内存
1. IPC共享内存区页在页框回收的时候，可以被换出到磁盘。 
```
sys_shmat()   #把共享内存挂到进程上

sys_shmdt()  #共享内存剥离。
```
