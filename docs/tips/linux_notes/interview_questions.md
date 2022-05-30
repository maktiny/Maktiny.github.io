## 阿里

1.  用一行命令查看文件的最后五行
* 从第3000行开始，显示1000行。即显示3000~3999行
cat filename | tail -n +3000 | head -n 1000
* 分解 
tail -n 1000：显示最后1000行

tail -n +1000：从1000行开始显示，显示1000行以后的

head -n 1000：显示前面1000行

2. 如何实现一个高效的单向链表逆序输出？
* 链表的翻转

3. 已知sqrt(2)约等于1.414，要求不用数学库，求sqrt(2)精确到小数点后10位

```c

const double EPSILON = 0.0000000001;

double sqrt2() {
    double low = 1.4, high = 1.5;
    double mid = (low + high) / 2;

    while (high - low > EPSILON) {
        if (mid * mid > 2) {
            high = mid;
        } else {
            low = mid;
        }
        mid = (high + low) / 2;
    }

    return mid;
}

```
4. 给定一个二叉搜索树(BST)，找到树中第 K 小的节点
* 二叉搜索树的中序遍历是有序的
```c
class Solution {
public://左根右-->逆序---> 右根左
    void traverse(TreeNode* root, int k ,int &ret, int &result){
        if(root == nullptr) return ;
        traverse(root->right,k,ret, result);
        ret++;

        if(k == ret) {
           result = root->val;
           return;
        }
        traverse(root->left, k ,ret, result);
        //return nullptr;
    }

    int kthLargest(TreeNode* root, int k) {
        int ret = 0;
        int result = 0;
         traverse(root ,k,ret,result);
        return result;
    }
};

```
 5. LRU缓存机制


 6. 输入 ping IP 后敲回车，发包前会发生什么？
 * 先查询ARP(IP --> MAC地址转换协议)缓存，命中则直接发出,否则在子网中广播ARP报文，询问网关的mac地址


7. 给定一个链表，删除链表的倒数第 N 个节点
* 双指针，间隔N

8. 输入一个递增排序的数组和一个数字s，在数组中查找两个数，使得它们的和正好是s。如果有多对数字的和等于s，则输出任意一对即可。

```c
class Solution {
public:
    vector<int> twoSum(vector<int>& nums, int target) {
        unordered_set<int>set;
        int size = nums.size();
        int temp = 0;
        vector<int>ret;
        for (int i = 0; i < size; ++i){
            temp = target - nums[i];
            if( set.count(temp)){
                ret.push_back(nums[i]);
                ret.push_back(temp);
                return ret;
            }

            set.insert(nums[i]);
        }
        return ret;
    }
};

```
9. 假如给你一个新产品，你将从哪些方面来保障它的质量？
* 在代码开发阶段，有单元测试、代码Review、静态代码扫描等；

* 测试保障阶段，有功能测试、性能测试、高可用测试、稳定性测试、兼容性测试等；

* 在线上质量方面，有灰度发布、紧急回滚、故障演练、线上监控和巡检等。

2. 多路复用I/O就是select，poll，epoll等操作，复用的好处就在于单个进程就可以同时处理多个网络连接的I/O
* 每次调用select，都需要把fd集合从用户态拷贝到内核态，这个开销在fd很多时会很大
* 同时每次调用select都需要在内核遍历传递进来的所有fd，这个开销在fd很多时也很大
* select支持的文件描述符数量太小了，默认是1024

* poll的机制与select类似, 但是poll没有最大文件描述符数量的限制
[select](https://vdn1.vzuu.com/SD/349279b4-9119-11eb-85d0-1278b449b310.mp4?disable_local_cache=1&bu=078babd7&c=avc.0.0&f=mp4&expiration=1653311333&auth_key=1653311333-0-0-ca1abc609b69e932001e637fe2682ee5&v=hw&pu=078babd7)

* 表面上看epoll的性能最好，但是在连接数少并且连接都十分活跃的情况下，select和poll的性能可能比epoll好，毕竟epoll的通知机制需要很多函数回调。
select低效是因为每次它都需要轮询。但低效也是相对的，视情况而定，也可通过良好的设计改善
[epoll](https://vdn1.vzuu.com/SD/346e30f4-9119-11eb-bb4a-4a238cf0c417.mp4?disable_local_cache=1&bu=078babd7&c=avc.0.0&f=mp4&expiration=1653311400&auth_key=1653311400-0-0-f17bd09b45209872f3ee2ad6cd86b63f&v=hw&pu=078babd7)

## 华为

1. static有什么用途？
* 限制变量的作用域：当我们同时编译多个文件时，所有未加static前缀的全局变量和函数都具有全局可见性
而static静态变量只在当前源文件有效。
* static 的第三个作用是默认初始化为0
* 设置变量的存储域：存储在静态数据区

2. 引用和指针的区别
* 引用必须被初始化 ,指针不必
* 不存在指向空值的引用，但是存在指向空值的指针
* 引用初始化以后不能被改变，指针可以改变所指的对象

```c
    int i = 45;
    int* p;           //p是一个int型的指针（可以把int*当成是一个类型）
    int* &r = p; 相当于P的别名     //r是一个对指针p的引用（r是一个引用，它的类型为int*）
    r = &i;           //r引用了一个指针，因此给r赋值&i就是令p指向i
    *r = 0;           //解引用r得到i，也就是p指向的对象，将i的值改为0

```
3. 描述实时系统的基本特性
* 在特定时间内完成特定的任务,实时性与可靠性

4. 全局变量和局部变量在内存中是否有区别
* 全局变量保存在内存的全局存储区中，占用静态的存储单元；局部变量保存在栈中，只有在所在函数被调用时才动态地为变量分配存储单元。

5. 堆栈溢出一般是由什么原因
* 函数调用层次太深
* 动态申请空间使用之后没有释放
* 数组访问越界
* 指针非法访问

6. 什么函数不能声明为虚函数
* 构造函数；
3、内联函数；
4、静态成员函数；
5、友元函数；
6、不会被继承的基类的析构函数

7. 请写出 float x 与“零值”比较的 if 语句：
```c
const float EPSILON = 0.00001;
if ((x >= - EPSILON) && (x <= EPSILON)

```
8. Internet采用TCP/IP网络协议？该协议的主要层次结构？
![2022-05-23 22-38-09 的屏幕截图.png](http://tva1.sinaimg.cn/large/0070vHShly1h2ipx2omrjj30ly0ke45a.jpg)

9. IP地址由两部分组成，网络号和主机号。

10. 在IA-32体系中，表示该分配阶对应的页数HUGETLB_PAGE_ORDER = 10，所以大页的长度是4M(1024个页大小),小页4KB.IA-64体系结构中HUGETLB_PAGE_ORDER = 第二大的order,可以自己设置

11. switch语句后的控制表达式只能是short、char、int、long整数类型和枚举类型，不能是float，double和boolean类型

12. IEEE 802.3u 标准:是快速以太网的标准，带宽100Mbps

13. 路由器要有这些特点：
1.至少支持两个网络接口
2.协议至少要实现到网络层
3.至少支持两种以上的子网协议
4.至少具备一个备份口
5.具有存储,转发和寻径功能

14. CSMA/CD 载波监听多路访问技术。
* CSMA/CD 应用在 OSI 的第二层   数据链路层
* CSMA/CD 采用   IEEE 802.3 标准
发送前空闲检测，只有信道空闲才发送数据
发送过程中冲突检测，若有冲突发生则需避让
先听后发，边听边发，冲突即停，延迟重发

15. VLAN的主要作用有？
VLAN（virtual local area network）虚拟局域网，把大的局域网划分为几个单独的互不相通的虚拟局域,限制广播域



## 

1. cache一致性协议
 MESI协议:
M(Modified)
这行数据有效，数据被修改了，和内存中的数据不一致，数据只存在于本Cache中。
E(Exclusive)
这行数据有效，数据和内存中的数据一致，数据只存在于本Cache中。
S(Shared)
这行数据有效，数据和内存中的数据一致，数据存在于很多Cache中。
I(Invalid)
这行数据无效。
[参考](https://blog.csdn.net/muxiqingyang/article/details/6615199)

2. 内存序：为了提高计算机的性能，编译器在编译程序的时候会对代码进行重排，
内存的排序既可能发生在编译器编译期间，也可能发生在 CPU 指令执行期间。
  内存屏障
3. 内存管理

4. 内核态和用户态的区别：内核态特权级0，可以使用特权指令；用户态特权级3，
  
5. malloc new brk mmeorymap
[参考](https://blog.csdn.net/weixin_39940770/article/details/110588878)
6. slab分配器，伙伴系统

7. c++ 偏特化模板：模板中的部分类型明确
 类模板和函数模板都可以被全特化；
 类模板能偏特化，不能被重载；
 函数模板全特化，不能被偏特化，可以重载。
 [参考](https://blog.csdn.net/lyn_00/article/details/83548629)
8. 构造析构
构造函数：建立对象时自动调用的函数
析构函数：对象的所有引用都被删除或者当对象被显式销毁时执行
[参考](https://baijiahao.baidu.com/s?id=1707202523649611541&wfr=spider&for=pc)
10. 多重继承,多继承



