### 开启 gdm3的custom.conf中的WaylandEnable, ubuntu22.04黑屏问题
* 腾讯会议不能使用，网络搜索开启 gdm3的custom.conf中的WaylandEnable, 导致ubuntu22.04黑屏问题
* 解决方案
```
重启 使用 advanced ubuntu -----> 选择recover mode启动----> 选择root drop to root shell prompt进入系统的root权限模式， 就可以修改一些系统配置---> /etc/gdm3/custom.conf
```
