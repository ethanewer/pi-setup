# Mailman 3 — delivery route optimization

A mailman must deliver to four houses labeled `A`, `B`, `C`, `D`. The mailman starts at house `A` and must visit the other three houses exactly once each, returning nowhere (the route ends after the fourth house). The goal is a route of **minimum total distance**.

Symmetric distances between houses (same both directions):

```
A-B = 5    A-C = 3    A-D = 7
B-C = 4    B-D = 6
C-D = 5
```

Enumerate the candidate orders (start `A` fixed):

```
A-B-C-D = 5+4+5 = 14
A-B-D-C = 5+6+5 = 16
A-C-B-D = 3+4+6 = 13   <-- minimum
A-C-D-B = 3+5+6 = 14
A-D-B-C = 7+6+4 = 17
A-D-C-B = 7+5+4 = 16
```

The optimal route is **A → C → B → D** with total distance **13**.

Write the route (house letters, comma-separated) and the total distance to `/app/answer.json`:

```json
{
  "route": "A,C,B,D",
  "total_distance": 13
}
```