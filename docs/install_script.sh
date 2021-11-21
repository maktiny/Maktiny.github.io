#!/bin/bash
#安装基本依赖
echo sudo apt-get install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen
echo sudo apt-get install git make npm yarn cargo bear cppman


#设置终端网络代理
echo export https_proxy=http://locahost:1089
echo export http_proxy=http://localhost:1089
echo export ALL_PROXY=http://localhost:1089
echo export all_proxy=http://localhost:1089

#安装vscode 和chrome
echo cd Downloads
echo sudo snap install --classic code
echo wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
echo sudo dpkg -i google-chrome-stable_current_amd64.deb

#克隆自己github 主页资料
echo mkdir homepage && cd homepage
echo git clone git@github.com:Maktiny/Maktiny.github.io.git
echo cd ~

#手动编译neovim
echo git clone https://github.com/neovim/neovim && cd neovim
echo make CMAKE_BUILD_TYPE=Release -j8
echo sudo make install

#安装spacevim
echo curl -sLf https://spacevim.org/cn/install.sh | bash

#yarn/npm 使用国内镜像
echo npm config set registry https://registry.npm.taobao.org/
echo yarn config set registry https://registry.npm.taobao.org/

echo sudo apt install ccls

echo sudo apt install xclip
echo sudo pip3 install neovim
echo sudo pip3 install pynvim
echo cargo install tree-sitter-cli
echo ln -s $(which fdfind) ~/.local/bin/fd
echo 
echo 

echo cd ~ # 保证在根目录
echo rm -r .SpaceVim.d # 将原来的配置删除
echo git clone https://github.com/martins3/My-Linux-config .SpaceVim.d 
echo nvim # 打开vim 将会自动安装所有的插件
