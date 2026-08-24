# Model Training Task: Adaptive Learning Rate with Gradient Clipping

## Task Overview
Implement a neural network training system with advanced optimization techniques including gradient accumulation, gradient norm clipping, and adaptive learning rate scheduling.

## Provided Files
- `data_generator.py`: Script to generate synthetic dataset
- This README with task instructions

## Expected Outputs
1. `/app/output/training_log.json`: JSON log of training metrics per epoch
2. `/app/output/best_model.pth`: PyTorch model checkpoint
3. `/app/output/summary.txt`: Text summary of training results

## How to Start
1. First run the data generator:
   ```bash
   python /app/data_generator.py
   ```
2. Implement your solution in `train_model.py`
3. Run your implementation:
   ```bash
   python train_model.py
   ```

## Evaluation
Your solution will be tested on:
- Correct implementation of optimization techniques
- Proper logging and model saving
- Handling of edge cases
- Memory and runtime efficiency

## Notes
- Set random seeds for reproducibility
- Use PyTorch for neural network implementation
- Handle class imbalance appropriately
- Maximum runtime: 5 minutes