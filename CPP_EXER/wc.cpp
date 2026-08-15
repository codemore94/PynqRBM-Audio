#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <cctype>
using namespace std;

class WordCounter{
  public:
    WordCounter(int value,string lg,vector<int>wc,map<int,string>wds);
    void change(int diff);
  void clear_value();
  void print_value();

  private:
    int value_;
    string longest_;
    vector<int>word_vec_;
    map<int,string>words_;
};

WordCounter::WordCounter(int value,string lg,vector<int>wc,map<int,string>wds){
  value_ = value;
}
void WordCounter::change(int diff){
  value_+=diff;
}
void WordCounter::clear_value(){
  value_=value_ & 0x00000000;
}
void WordCounter::print_value(){
  cout<<"value: " <<value_ << endl;
}
string LongestWord(string sen) {
  
  // code goes here
  WordCounter wc(0,"",{},{});
  string longest;
  string word;
  vector<int>word_vec;
  map<int,string>words;
  int counter = 0;  

  for(char& c:sen){
    if(isspace(c)){
      words.insert(std::make_pair(counter,word));
      word.clear();
      counter =0;
      wc.clear_value();
      
    }
    else if(isalpha(c)){
      ++counter;
      word+=c;
      wc.change(1);
      cerr <<"tmp: " << counter << word << endl;
      wc.print_value();
    }
  }

  for(auto iter:words){
    word_vec.push_back(iter.first);
  }
  std::sort(word_vec.begin(),word_vec.end());

  if((--(words.end()) != words.end())){
    longest=(--(words.end()))->second;
  } 
  return words[word_vec.at(0)];

}

// keep this function call here
int main(void) { 
   
  cout << LongestWord(coderbyteInternalStdinFunction(stdin));
  return 0;
    
}
