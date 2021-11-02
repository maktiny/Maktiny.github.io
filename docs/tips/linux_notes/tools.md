# tips of some tools using
## shell 
1. find . -name "*.c" | xargs rm -rfv  批量刪除當前目錄下的.c文件
2. grep -rn "内容" 路径  #遍历路径下的所有文件，字符串匹配" "中的内容
3. 
4. 
5. 
6. 
7. 
8. 
9. 
10.
11.
12.
13.
14.
15.

## fmt
1. echo ':x86_64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/tmp/qemu-x86_64:C' > /proc/sys/fs/binfmt_misc/register
   echo -1 > 文件路径, 当一个文件不能写入的时候， ”echo -1 > 路径“ 修改权限并清空


## tmux 
tmuew -s name      创建会话
tmuetach           离开会话，会话线程继续存在
tmux ls               显示会话数
tmux attach -t name   连接会话
tmux kill-session -t name 杀死会话等于exit
tmux switch -t name   切换会话
tmux split-window -h   把会话分成左右两个窗口
Ctrl+b+;              光标在两个窗口切换
Ctrl+b+o              左右两个窗口换位  

## vim
vim a.txt b.txt    同时编辑两个文件
：n        跳转到上一个文件
：N        跳转到下一个文件
：w        保存
：q        退出
：set nu   设置行号
：set nonu 删除行号
：数字     跳转到该行

## git 
1. git remote add origin <git URL>   #仓库提交的的远程服务器
2. git checkout -b <branch name>     #创建并切换分支 
3. git branch -d  <branch name>      #删除分支
4. git merge <branch name>           #合并分支到master,master位默认主分支
5. git diff <source branch> <target branch> #比较两个分支的不同法
6. git log --author=bob               #只查看bob的提交历史
7. git checkout --<filename>  #使用本地HEAD替换工作区的文件，提交到index暂存区的数据不受影响
8. git fetch origin 
git reset --hard master #放弃本地修改，从远端拿最新的历史版本，并将本地分支指向它
9. git rebase -i HEAD~number #合并最新提交记录commit往前number个commit到一条提交记录
10. git reset --soft HEAD^1
    git commit --amend  #合并两个commit为一个
11. 如果你想放弃这次压缩的话，执行以下命令：
      git rebase --abort

