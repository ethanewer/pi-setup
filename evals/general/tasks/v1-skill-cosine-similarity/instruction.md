`/app/a.json` and `/app/b.json` each contain two arrays of numbers of equal length, as:
```json
[3.0, 5.0, 2.0, 8.0, 4.0]
```
Write a program `/app/cosim.py` that:
1. loads both vectors, 
2. computes the cosine similarity:
   cos = (a·b) / (|a| · |b|)  where |v| is the Euclidean norm,
3. if either vector has zero norm, the result is 0.0,
4. writes the cosine (a float, rounded to 6 decimals) to `/app/sim.txt`.

Run `/app/cosim.py` so `/app/sim.txt` is produced. The verifier recomputes the cosine similarity from the same vectors and compares within tolerance.