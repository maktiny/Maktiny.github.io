-- defines a factorial function
local function fact (n) --函数默认是全局的，除非声明local
 if n == 0 then
 	return 1
 else
 	return n * fact(n - 1)
 end
end

print("enter a number:")
--a = io.read("*n") -- reads a number
--print(fact(a))
io.write("Hello world, from ",_VERSION,"!\n")
local fruit = "apples".."oranges" --lua字符串拼接
io.write(fruit,"\n")
io.write(#fruit, "\n") --字符串长度

--for循环
for i = 10, 1, -1
do
	--if else
	if i > 5
	then
		print(i)
	elseif i == 3
	then
		print("else if")
	else
		print("fuck")
	end
end

--while 循环
local a = 10
while a > 1
do
	print(a);
	a = a -1
end

--repeate until循环
local b = 0
repeat
	print("lili: ", b)
	b = b + 1
until b > 10



local function mprint(num)
	print("there is myprint: ", num)
end

--[[ lua也可以把函数当作指针进行参数传递--]]
local function add(num1, num2, functionpointer)
	local result = num1 + num2
	functionpointer(result)
end

mprint(10)
add(2,5, mprint)

--参数个数不确定的函数
--pairs会遍历表中的所有key-value的值，
--ipairs会根据key的值从1开始加1递增遍历对应的table[i]的值，
--直到出现第一个不是按1递增的值
--pairs遍历的顺序不确定，它是和hash值相关，ipairs是根据i的顺序遍历的
local function average(...)
	local result  = 0
	local arg = {...} --把参数变成表
	for key, value in ipairs(arg) do
		result = result + value
	end
	return  result / #arg
end

print("average is ", average(1,2,3,4,5))

--数组的下标从1开始
local arr = {"lua", "tutorial"}
for i = 0, 2 do --默认步长是1
	print(arr[i])
end

--lua的数组是table实现的，所以下标可以任意
local array = {}
for i = -2, 2 do
	array[i] = i * 2
end

for i = -2, 2 do
	print(array[i])
end

--多维数组的声明方式
local ar = {}
for i = 1, 3 do
	ar[i] = {}
	for j = 1, 3 do
		ar[i][j] = i * j
	end
end

for i = 1, 3 do
	for j = 1, 3 do
		io.write(" ",ar[i][j])
	end
	io.write("\n")
end

--迭代器ipairs
local array = {"hello", "world", "!"}

for key, value in ipairs(array) do
	print(key, value)
end

--自己实现迭代器
local function eleIterator (collect)
	local index = 0
	local count = #collect

	-- 返回一个族函数
	return function ()
		index = index + 1
		if index <= count then
			return collect[index]
		end
	end

end

for element in eleIterator(array) do
	print(element)
end


--lua最重要的数据结构table
--它的索引可以是数字，也可以是字符串
--当释放的时候置为 nil
--它的长度可以动态增长
local mytable = {}
mytable[1] = "fuck you"
mytable["bitch"] = "it's you"
print(mytable.bitch)
--表赋值，当 lal置为nil时，mytable还能正常访问
--其时是两个指针指向同一个table，lal改变，mytable改变
local lal = mytable

lal["bitch"] = "?"
print(mytable[1])
print(mytable["bitch"])
lal = nil
print(mytable["bitch"])



twotable = {4,5,6}

--可以在表中进行运算符的重载，
--还可以添加__call, __tostring等函数，在使用table的时候，自动调用
local mtable = setmetatable({1,2,3}, {
	__add = function(mtable, newtable)
		for i = 1, #newtable do
			local count = #mtable
			table.insert(mtable, count + 1, newtable[i])
		end
		return mtable
	end
})

mtable = mtable + twotable
for key, value in ipairs(mtable) do
	print(key, value)
end



co = coroutine.create(function (value1,value2)
   local tempvar3 = 10
   print("coroutine section 1", value1, value2, tempvar3)

   local tempvar1 = coroutine.yield(value1+1,value2+1)
   tempvar3 = tempvar3 + value1
   print("coroutine section 2",tempvar1 ,tempvar2, tempvar3)

   local tempvar1, tempvar2= coroutine.yield(value1+value2, value1-value2)
   tempvar3 = tempvar3 + value1
   print("coroutine section 3",tempvar1,tempvar2, tempvar3)
   return value2, "end"
end)

print("main", coroutine.resume(co, 3, 2))
print("main", coroutine.resume(co, 12,14))
print("main", coroutine.resume(co, 5, 6))
print("main", coroutine.resume(co, 10, 20))


--lua的所有数字的类型(整形，浮点)都是number
--error的处理: assert
local function add(a, b)
	assert(type(a) == "number", "a is a number")
	assert(type(b) == "number", "b is a number")
	return a + b
end

--add(10)

local function myfunction (n)
	return n / nil
end
--pcall 把函数调用在受保护的模式下进行
if pcall(myfunction, 10) then
	print("success")
else
	print("function call is wrong!")
end

--xcall可以捕获错误信息，使用错误处理函数，
function myerr(err)
	print("ERROR: ", err)
end
local status = xpcall(myfunction, myerr, 10)
print(status)


--文件操作

local file = io.open("test.lua", "a+")
--把打开的文件作为输出源
io.input(file)
--输出打开文件的第一行
print(io.read())
--把打开文件作为输入源
io.output(file)
local string = "--hello , world"
--把string写入到文件中
io.write(string, "\n")
io.close(file)





--lua支持面向对象的机制
-- Meta class
Shape = {area = 0}

-- Base class method new

function Shape:new (o,side)
   o = o or {}
   setmetatable(o, self)
   self.__index = self
   side = side or 0
   self.area = side*side;
   return o -- object
end

-- Base class method printArea

function Shape:printArea ()
   print("The area is ",self.area)
end

-- Creating an object
myshape = Shape:new(nil,10)
myshape:printArea()

Square = Shape:new()

-- Derived class method new

function Square:new (o,side)
   o = o or Shape:new(o,side)
   setmetatable(o, self)
   self.__index = self
   return o
end

-- Derived class method printArea

function Square:printArea ()
   print("The area of square is ",self.area)
end

-- Creating an object
mysquare = Square:new(nil,10)
mysquare:printArea()

--lua的继承是通过赋值实现的,然后重写构造函数和成员函数
Rectangle = Shape:new()
-- Derived class method new

function Rectangle:new (o,length,breadth)
   o = o or Shape:new(o)
   setmetatable(o, self)
   self.__index = self
   self.area = length * breadth
   return o
end

-- Derived class method printArea

function Rectangle:printArea ()
    print("The area of Rectangle is ",self.area)
end

-- Creating an object

myrectangle = Rectangle:new(nil,10,20)
myrectangle:printArea()

--lua的垃圾收集机制
print(collectgarbage("collect")) --Runs one complete cycle of garbage collection.
print(collectgarbage("count"))



