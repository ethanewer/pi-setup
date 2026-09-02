Given a small discrete dataset, you must learn a dependency structure among the variables by estimating pairwise mutual information and building a maximum-weight spanning tree (this is the Chow-Liu algorithm).

The dataset is a CSV at `/app/data.csv` with a header line `A,B,C,D` followed by numeric rows. All variables are integer-coded and their domains are small (0..max per column).

Write a program `/app/learn_edges.py` that:
1. reads `/app/data.csv`,
2. for every unordered pair of variables (u,v), estimates mutual information `I(u,v) = SUM_{a,b} p(a,b) * log2( p(a,b) / (p(a) * p(b)) )` using empirical joint/marginal frequencies, where a runs over u's domain and b over v's domain, and any zero-frequency term is treated as 0,
3. treats these MI scores as edge weights, and computes the *maximum spanning tree* over the 4 variables with a greedy (Kruskal-style) algorithm: sort all candidate edges by descending weight then by (var1,var2) as tie-breakers, and add an edge only if it does not create a cycle,
4. writes `/app/edges.json` as a JSON array of the 3 selected undirected edges, each as `[var1, var2]` with var names sorted alphabetically, and the whole array sorted lexicographically by the pair.

Run your program to produce `/app/edges.json`. The verifier recomputes the same structure from the same data, so match the algorithm exactly.
