You are working with a catalog of **fluorescent proteins** and their peak emission wavelengths (in nm).

In `/app` there is a CSV file `/app/proteins.csv` with a header row and two columns: `name` and `peak_emission` (nm). It lists several proteins.

There is also `/app/query.txt` containing a single integer (a target wavelength in nm).

Write a script `/app/find.py` that:
1. Reads `/app/proteins.csv`.
2. Reads the target wavelength from `/app/query.txt`.
3. Finds the protein whose peak emission wavelength is **closest to the target** (absolute difference; if two are equidistant, pick the lower peak-emission in the file order).
4. Writes `/app/result.json` containing exactly `{"name": "<protein>", "peak_emission": <int>}`.

Run your script so `/app/result.json` contains the correct closest protein. Use `python3` (the csv module is standard).