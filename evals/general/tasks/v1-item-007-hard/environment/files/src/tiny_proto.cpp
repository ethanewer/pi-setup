#include "tiny_proto.h"
#include <fstream>
#include <cctype>
#include <algorithm>

static bool is_sp(unsigned char c){ return std::isspace(c)!=0; }

static void ltrim(std::string& s){
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](unsigned char c){ return !std::isspace(c); }));
}
static void rtrim(std::string& s){
    s.erase(std::find_if(s.rbegin(), s.rend(), [](unsigned char c){ return !std::isspace(c); }).base(), s.end());
}

bool proto_load(const std::string& path, protoMap& out){
    std::ifstream f(path);
    if(!f) return false;
    std::string line;
    while(std::getline(f, line)){
        std::string t = line;
        size_t p = t.find("//");
        if(p != std::string::npos) t = t.substr(0, p);
        ltrim(t);
        if(t.empty()) continue;
        size_t cc = t.find(':');
        if(cc == std::string::npos) continue;
        std::string k = t.substr(0, cc);
        std::string v = t.substr(cc + 1);
        ltrim(k); rtrim(k); ltrim(v); rtrim(v);
        if(v.size() >= 2 && v.front() == '"' && v.back() == '"') v = v.substr(1, v.size() - 2);
        if(!k.empty()) out.kv[k] = v;
    }
    return true;
}

std::string proto_get(protoMap& m, const std::string& k, const std::string& dflt){
    auto it = m.kv.find(k);
    return it == m.kv.end() ? dflt : it->second;
}