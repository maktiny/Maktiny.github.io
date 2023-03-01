#include <iostream>
#include <boost/filesystem.hpp>
//boost库中所有内容都写在一个文件中,所以后缀.hpp
using namespace std;

int main() {
	boost::filesystem::path path = "/usr/share/cmake/modules";

	if(path.is_relative()) {
		std::cout<<"path is real"<<std::endl;
	}
	else{
		std::cout<<"path is not real"<<std::endl;
	}
	return 0;
}
