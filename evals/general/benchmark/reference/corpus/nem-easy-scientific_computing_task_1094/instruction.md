## Numerical Integration of Environmental Data

You are analyzing environmental sensor data that records temperature measurements at irregular time intervals. Your task is to process this data and compute the total thermal energy accumulated over the observation period using numerical integration.

## Your Task

1. **Read the input data** from `/app/sensor_data.json`. The file contains a JSON object with:
   - `timestamps`: Array of Unix timestamps (seconds) when measurements were taken
   - `temperatures`: Array of temperature values in Celsius at corresponding timestamps
   - `baseline_temp`: Reference baseline temperature in Celsius (typically room temperature)
   
   Example structure:
   ```json
   {
     "timestamps": [0, 300, 900, 1800],
     "temperatures": [22.5, 23.1, 24.8, 22.9],
     "baseline_temp": 21.0
   }
   ```

2. **Compute thermal energy accumulation** using numerical integration:
   - For each measurement, calculate the temperature difference: ΔT = temperature - baseline_temp
   - The thermal energy per unit area accumulated between timestamps tᵢ and tᵢ₊₁ is approximated by:
     ```
     energy_segment = (ΔTᵢ + ΔTᵢ₊₁)/2 × (tᵢ₊₁ - tᵢ)
     ```
     This uses the trapezoidal rule for integration.
   - Sum all segments to get the total accumulated thermal energy.

3. **Generate the output report** in `/app/energy_report.json` with the following structure:
   ```json
   {
     "total_energy": <float: total accumulated thermal energy in °C·s>,
     "segments": [
       {
         "start_time": <int: start timestamp>,
         "end_time": <int: end timestamp>, 
         "energy": <float: energy for this segment>
       },
       ... (one object for each time interval)
     ],
     "average_temp_deviation": <float: mean of all ΔT values>,
     "processing_summary": {
       "data_points": <int: number of measurements>,
       "time_span": <int: total observation time in seconds>,
       "integration_method": "trapezoidal"
     }
   }
   ```

4. **Validation requirements**:
   - All numerical values should be floats (not integers in the JSON)
   - The segments array should contain n-1 objects where n is the number of data points
   - Round floating point values to 3 decimal places for consistency
   - Handle edge cases: if there's only one data point, total_energy should be 0.0 and segments should be an empty array

## Expected Outputs
- `/app/energy_report.json`: JSON file with the complete analysis results as specified above

## Test Verification
The tests will verify:
1. The output file exists and is valid JSON
2. All required fields are present with correct types
3. Numerical calculations are correct within 0.001 tolerance
4. The segments array has the correct length
5. Edge cases are handled properly