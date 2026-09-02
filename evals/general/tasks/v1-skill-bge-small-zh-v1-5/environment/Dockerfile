FROM bench-base:python-3.12
WORKDIR /app
RUN python3 - <<'PYEOF'
import json
sentences = [
    '如何使用API接口',
    '这个程序运行很快',
    '天气很好适合散步',
    '今天适合去公园',
    '训练一个机器学习模型',
    '如何接入大模型接口'
]
def gen(dim, seed):
    out = []
    x = seed
    for _ in range(dim):
        x = (x * 1103515245 + 12345) & 0x7fffffff
        out.append((x % 1000) / 1000.0 - 0.5)
    return out
vecs = [gen(768, i * 9991 + 7) for i in range(len(sentences))]
json.dump({'sentences': sentences, 'embeddings': vecs}, open('/app/embed.json', 'w'))
PYEOF
