In `/app` there is a text file `lines.txt` containing these three lines, in this order:

```
alpha
beta
gamma
```

Use the **vim** editor (not sed, python, or a plain file overwrite) to reorder the file so that its lines become, in this exact order:

```
alpha
gamma
beta
```

(That is, move the middle line `beta` so it comes after `gamma`.) Save the file. The final on-disk content of `/app/lines.txt` is what will be verified; it must be exactly the three lines above (each followed by a newline).