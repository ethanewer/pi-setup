FROM bench-base:python-3.12

WORKDIR /app

# Fixed query/key/value matrices for the attention computation.
RUN python3 - <<'EOF'
Q = [[1.0,0.0,0.0],[0.0,1.0,1.0],[1.0,1.0,0.0]]
K = [[0.0,1.0,0.0],[1.0,0.0,1.0],[0.0,0.0,1.0]]
V = [[1.0,2.0,3.0],[4.0,5.0,6.0],[7.0,8.0,9.0]]
with open("/app/attn_input.py","w") as f:
    f.write("Q = " + repr(Q) + "\n")
    f.write("K = " + repr(K) + "\n")
    f.write("V = " + repr(V) + "\n")
EOF