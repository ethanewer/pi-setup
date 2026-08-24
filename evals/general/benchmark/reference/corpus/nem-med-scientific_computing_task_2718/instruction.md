# Simulation of Electron Trajectory in a Paul Trap

You are tasked with implementing a numerical simulation of an electron's motion in a Paul (quadrupole) ion trap. Paul traps use oscillating electric fields to confine charged particles, creating complex 3D trajectories. This task requires implementing the equations of motion, numerical integration, and proper data output.

## Background

A Paul trap consists of a ring electrode and two endcap electrodes. The potential is given by:

Φ(x,y,z,t) = U₀ * cos(ωt) * (x² + y² - 2z²) / (2r₀²)

Where:
- U₀ is the applied voltage amplitude
- ω is the angular frequency of the oscillating field
- r₀ is the characteristic trap radius (distance from center to ring electrode)
- (x,y,z) are spatial coordinates

The force on an electron (charge q = -e) is F = q * (-∇Φ). The equations of motion become:

d²x/dt² = -(q/m) * (U₀/r₀²) * cos(ωt) * x
d²y/dt² = -(q/m) * (U₀/r₀²) * cos(ωt) * y  
d²z/dt² = +(2q/m) * (U₀/r₀²) * cos(ωt) * z

## Your Task

Implement a simulation that:

1. **Parse Configuration**: Read simulation parameters from `/app/config.json` (provided). The file contains:
   - `U0_volts`: Applied voltage amplitude in volts
   - `frequency_hz`: Oscillation frequency in Hz
   - `r0_meters`: Trap radius in meters
   - `initial_position`: [x0, y0, z0] in meters
   - `initial_velocity`: [vx0, vy0, vz0] in m/s
   - `simulation_time`: Total simulation time in seconds
   - `time_step`: Integration time step in seconds
   - `output_frequency`: How often to record positions (every N steps)

2. **Implement Numerical Integration**: 
   - Use the Velocity Verlet algorithm (second-order symplectic integrator)
   - Handle the time-dependent force F(t) = F₀ * cos(ωt) * position_component
   - Mass of electron m = 9.1093837e-31 kg, charge q = -1.602176634e-19 C

3. **Run Simulation**:
   - Simulate the electron's trajectory for the specified duration
   - Record position and velocity at intervals specified by `output_frequency`
   - Track total energy (kinetic + potential) at each recording step

4. **Analyze Results**:
   - Compute the final displacement from origin: √(x² + y² + z²)
   - Determine if electron remains confined (displacement < 2*r0 at all times)
   - Calculate maximum kinetic energy during simulation

5. **Output Results**:
   - Save trajectory data to `/app/output/trajectory.csv` with columns: `time,x,y,z,vx,vy,vz,energy`
   - Save summary statistics to `/app/output/summary.json` with structure:
     ```json
     {
       "final_displacement_m": float,
       "max_displacement_m": float,
       "confined": boolean,
       "max_kinetic_energy_j": float,
       "energy_conservation_error": float,
       "num_steps": integer
     }
     ```
   - Create a plot visualization at `/app/output/trajectory.png` showing:
     - 3D trajectory (x, y, z) with color indicating time
     - Projections on xy, xz, yz planes as insets
     - Include labels and title "Electron Trajectory in Paul Trap"

## Expected Outputs

- `/app/output/trajectory.csv`: CSV file with 8 columns as described
- `/app/output/summary.json`: JSON file with summary statistics
- `/app/output/trajectory.png`: PNG image of the 3D trajectory plot

## Notes

- The Velocity Verlet algorithm for time-dependent forces:
  v(t+Δt/2) = v(t) + (F(t)/m) * Δt/2
  x(t+Δt) = x(t) + v(t+Δt/2) * Δt
  v(t+Δt) = v(t+Δt/2) + (F(t+Δt)/m) * Δt/2

- Potential energy at time t: U = q * Φ(x,y,z,t)
- Total energy: E = ½m(vx²+vy²+vz²) + U

- Ensure all calculations use SI units consistently
- The simulation should handle edge cases (e.g., zero initial velocity, starting at origin)
- Energy conservation error = |(E_final - E_initial)/E_initial| (use absolute value)

## Success Criteria

The tests will verify:
1. Output files exist with correct names and formats
2. CSV file has correct number of columns and rows (based on simulation_time/time_step/output_frequency)
3. JSON summary contains all required keys with appropriate data types
4. Trajectory remains physically plausible (no NaN/infinite values)
5. Energy conservation error is reasonable (< 1e-3 for this integrator)
6. Plot file exists and is valid PNG