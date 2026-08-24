# Stochastic Simulation of Two-State Chemical System

You are tasked with implementing a simple stochastic simulation of molecules transitioning between two states (A and B). This models basic chemical reactions like isomerization or protein conformational changes.

## Background

Consider a system with N identical molecules. Each molecule can be in either state A or state B. At each discrete time step, molecules in state A transition to state B with probability `p_AB`, and molecules in state B transition to state A with probability `p_BA`. Transitions are independent and stochastic.

The simulation will track the population of molecules in each state over time.

## Your Task

Read the simulation parameters from `/app/parameters.json`, perform the stochastic simulation, and write two output files.

### Step 1: Read Parameters
Read the JSON file at `/app/parameters.json` containing:
- `N`: total number of molecules (positive integer)
- `p_AB`: probability that a molecule in state A transitions to state B per time step (float between 0 and 1)
- `p_BA`: probability that a molecule in state B transitions to state A per time step (float between 0 and 1)
- `initial_A`: initial number of molecules in state A (integer between 0 and N)
- `time_steps`: number of time steps to simulate (positive integer)
- `seed`: random seed for reproducibility (integer)

### Step 2: Initialize System
- Set the random seed using the provided `seed` value.
- Initialize the system with `initial_A` molecules in state A and the remaining `N - initial_A` molecules in state B.
- Create a data structure to track the population counts over time.

### Step 3: Perform Stochastic Simulation
For each time step from 1 to `time_steps`:
1. For molecules currently in state A: generate random numbers to determine which transition to B (with probability `p_AB`).
2. For molecules currently in state B: generate random numbers to determine which transition to A (with probability `p_BA`).
3. Update the state counts based on these transitions.
4. Record the counts of molecules in state A and state B at the end of this time step.

### Step 4: Compute Summary Statistics
After the simulation, compute:
- `final_A`: number of molecules in state A at the final time step
- `final_B`: number of molecules in state B at the final time step
- `equilibrium_estimate`: estimated equilibrium fraction of molecules in state A, computed as the average fraction over the last 10% of time steps (or all steps if fewer than 10 steps). This should be a float between 0 and 1.

### Step 5: Write Output Files
Create two output files:

1. **Time series data** (`/app/trajectory.csv`):
   - CSV file with headers: `time_step,count_A,count_B`
   - Each row corresponds to one time step (0 to `time_steps`)
   - Row 0 should contain the initial counts
   - Rows 1 through `time_steps` should contain counts after each simulation step
   - Example format:
     ```
     time_step,count_A,count_B
     0,80,20
     1,75,25
     2,73,27
     ```

2. **Summary statistics** (`/app/summary.json`):
   - JSON file with the following structure:
     ```json
     {
       "parameters": {
         "N": 100,
         "p_AB": 0.1,
         "p_BA": 0.2,
         "initial_A": 80,
         "time_steps": 50,
         "seed": 42
       },
       "results": {
         "final_A": 65,
         "final_B": 35,
         "equilibrium_estimate": 0.647
       }
     }
     ```
   - The `parameters` object should contain the exact values read from the input file.
   - The `results` object should contain your computed statistics with `final_A` and `final_B` as integers and `equilibrium_estimate` as a float rounded to 3 decimal places.

## Expected Outputs
- `/app/trajectory.csv`: CSV file with time series data
- `/app/summary.json`: JSON file with parameters and summary statistics

## Success Criteria
1. Both output files must be created at the specified paths.
2. The CSV file must have exactly `time_steps + 1` rows (including header).
3. The JSON file must be valid JSON and contain all required fields.
4. The simulation must be reproducible using the given seed.
5. Counts must always sum to N at every time step.
6. The equilibrium estimate must be calculated correctly as described.

## Hints
- Use `numpy.random` for random number generation with the provided seed.
- For efficiency, you can use vectorized operations on arrays of molecules rather than looping over each molecule individually.
- Remember that probabilities are per molecule per time step.
- The equilibrium fraction of state A is theoretically `p_BA / (p_AB + p_BA)` for this simple two-state system.