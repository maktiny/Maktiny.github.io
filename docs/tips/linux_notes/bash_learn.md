#!/bin/bash
# 字符串，变量

name="json"
echo "${name}"
echo "I am $(pwd)"
for i in {5..50};do
  echo "$i"
done


# 函数调用，参数传递

function my_info(){
  echo "I am in $(pwd)"
  echo "$1"
  echo "$0" #参数是文件名
}

a="$(my_info "nihao")" #函数调用，参数传递使用“”
echo "function call's result is $a"

function my_value(){
  echo "my_value222222222"
  return 5 #return 返回函数执行状态：
  #成功返回0 ，失败返回1-255，
  #可以把返回状态赋值给$? 然后获取
}
b=$(my_value)
echo " test result  $?" #获取返回状态
echo "$b"

# 条件语句 数组
#if elif else 之会执行一个
array=('a' 'b' 'c' 'd')
echo ${array[1]}
if [[ ${array[0]} == 'a' ]];then
  echo "${array[0]}"
elif [[ ${array[-1]} == 'd' ]];then
  echo "${array[-1]}"
else 
  echo ${array[1]}
fi
echo "${!array[@]}" #0 1 2 3

# switch case 
echo -n "enter the name country:"
read country
case $country in
  chinese)
    echo "nihao";;
  american)
    echo "hello";;
  *) # * 缺省情况
    echo "I don't know"
esac
########################
# > a.txt 重定向到文件a.txt,每次都覆盖原来的内容
# >>      追加到a.txt
# 1>      1表示正确的输出，重定向
# 2>      2表示错误的输出

# >a.txt 2>&1 正确，错误的信息都重定向到a.txt
# 2>/dev/null 错误的信息都重定向到null，不输出

# &>/dev/null  正确，错误的信息都重定向到null，不输出
#
##############################
a
