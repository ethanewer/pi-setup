`/app/oracle.py` is a black box: it has no documentation, but it computes a deterministic pure function of one integer argument. If you run `python3 /app/oracle.py N`, it prints the integer output for input N. You never see its implementation.

Your task is to characterize the black box through input/output probing:
1. Run `/app/oracle.py` with several different integers and record inputs and outputs, until you are confident you understand the rule it computes.
2. Write a program `/app/model.py` that defines a function `model(n)` reproducing that same observed input/output behavior. (This is your own hypothesis; it need not call oracle.)
3. `/app/test_inputs.txt` lists 10 integer inputs, one per line. Using `model()`, compute the predicted output for each and write those 10 outputs, one per line, to `/app/predictions.txt`.

Produce `/app/predictions.txt`. The verifier quotes the oracle for these exact inputs and requires your predicted outputs to match every one.
