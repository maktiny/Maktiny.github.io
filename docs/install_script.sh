#!/bin/bash
#安装基本依赖
#sudo apt-get install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen
#sudo apt-get install git make npm yarn cargo bear cppman


#设置终端网络代理
#sudo export https_proxy="https://localhost:8889"
#sudo export http_proxy="http://localhost:8889"
#sudo export ALL_PROXY="http://localhost:8889"
#sudo export all_proxy="http://localhost:8889"

#sudo export https_proxy="socks5://localhost:1089"
#sudo export http_proxy="socks5://localhost:1089"

#安装vscode 和chrome
#echo cd Downloads
#echo sudo snap install --classic code
#echo wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#echo sudo dpkg -i google-chrome-stable_current_amd64.deb

#克隆自己github 主页资料
#echo mkdir homepage && cd homepage
#echo git clone git@github.com:Maktiny/Maktiny.github.io.git
#echo cd ~

#手动编译neovim
git clone https://github.com/neovim/neovim && cd neovim
sudo make CMAKE_BUILD_TYPE=Release -j8
sudo sudo make install

#安装spacevim
sudo curl -sLf https://spacevim.org/cn/install.sh | bash

#yarn/npm 使用国内镜像
sudo npm config set registry https://registry.npm.taobao.org/
sudo yarn config set registry https://registry.npm.taobao.org/

sudo sudo apt install ccls

sudo sudo apt install xclip
sudo sudo pip3 install neovim
sudo sudo pip3 install pynvim
sudo cargo install tree-sitter-cli
sudo ln -s $(which fdfind) ~/.local/bin/fd 
echo 

sudo cd ~ # 保证在根目录
sudo rm -r .SpaceVim.d # 将原来的配置删除
sudo git clone https://github.com/martins3/My-Linux-config .SpaceVim.d 
sudo nvim # 打开vim 将会自动安装所有的插件
