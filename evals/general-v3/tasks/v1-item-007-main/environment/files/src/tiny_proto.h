#pragma once
// Minimal Caffe-ish '.prototxt' key:value reader.
#include <map>
#include <string>

struct protoMap {
    std::map<std::string, std::string> kv;
};

bool proto_load(const std::string& path, protoMap& out);
std::string proto_get(protoMap& m, const std::string& key, const std::string& dflt = "");
