FROM bench-base:python-3.12

WORKDIR /app

# A small type of the DeepSeek BPE tokenizer: a merge table (rank 0 = top line)
# and the text to tokenize. Merges follow the format "<t1> <t2> <new-token>".
RUN cat > /app/merges.txt <<'EOF2'
a a A
b b B
a b C
EOF2

RUN cat > /app/text_src.txt <<'EOF2'
aa bb aa aabb
EOF2
