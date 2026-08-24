# Adaptive Learning Rate with Gradient Norm Clipping and Validation Early Stopping

You are building a training optimization system for a neural network model. Your task is to implement a training loop that combines three advanced optimization techniques:

1. **Gradient Accumulation** (simulating larger batch sizes)
2. **Gradient Norm Clipping** (preventing exploding gradients)
3. **Adaptive Learning Rate with Plateaus** (reducing LR when validation loss stagnates)

## Dataset and Model

You are given a synthetic classification dataset generated from the provided `data_generator.py`. The dataset consists of:
- 10,000 samples with 50 features each
- Binary classification labels (0 or 1)
- A class imbalance of 60:40

The model is a simple feed-forward neural network with:
- Input layer: 50 features
- Hidden layers: 128 → 64 → 32 units with ReLU activation and dropout (p=0.3)
- Output layer: 1 unit with sigmoid activation

## Your Task

Implement a training script `train_model.py` that:

### 1. Data Preparation (10 points)
- Load the dataset from `/app/data/train_data.npy` and `/app/data/train_labels.npy`
- Split into 80% training, 20% validation sets (stratified by label)
- Create DataLoaders with batch size = 32
- Apply feature normalization using training statistics only

### 2. Model Definition (15 points)
- Define the neural network architecture as specified above
- Initialize weights using Kaiming initialization for ReLU layers
- Track total parameters and print model summary

### 3. Training Loop with Advanced Optimizations (60 points)
Implement a training function with:

**A. Gradient Accumulation** (15 points)
- Accumulate gradients over 4 batches before optimizer step
- Effectively simulate batch size = 128
- Handle edge cases (final partial accumulation steps)

**B. Gradient Norm Clipping** (15 points)
- Clip gradients using `torch.nn.utils.clip_grad_norm_`
- Set max norm = 1.0
- Log average gradient norm per epoch
- Skip clipping if gradients are None or zero

**C. Adaptive Learning Rate with Early Stopping** (30 points)
- Implement custom scheduler `PlateauLR` that:
  - Monitors validation loss
  - Reduces LR by factor 0.5 when validation loss doesn't improve for 3 epochs
  - Has minimum LR = 1e-6
  - Resets patience when LR is reduced
- Implement early stopping if validation loss doesn't improve for 7 epochs
- Save best model checkpoint when validation loss improves

### 4. Monitoring and Output (15 points)
- Track and log metrics to `/app/output/training_log.json` with:
  - Epoch number
  - Training loss (averaged over accumulation steps)
  - Validation loss
  - Learning rate
  - Gradient norm (average)
  - Training time per epoch
- Save the best model to `/app/output/best_model.pth`
- Generate a summary report to `/app/output/summary.txt` containing:
  - Final validation accuracy
  - Total training time
  - Number of epochs trained
  - Learning rate reductions count
  - Early stopping triggered (True/False)

## Implementation Requirements

1. Use PyTorch for model implementation
2. Set random seeds for reproducibility (seed=42)
3. Use binary cross-entropy loss
4. Use Adam optimizer with initial LR=0.001
5. Train for maximum 50 epochs
6. Handle edge cases gracefully (empty batches, NaN values)
7. Include proper error checking and logging

## Expected Outputs

Your implementation must create:

1. `/app/output/training_log.json` - JSON array of epoch metrics
   Format: 
   ```json
   [
     {
       "epoch": 1,
       "train_loss": 0.6931,
       "val_loss": 0.6925,
       "learning_rate": 0.001,
       "grad_norm": 0.8543,
       "epoch_time": 2.34
     },
     ...
   ]
   ```

2. `/app/output/best_model.pth` - PyTorch model checkpoint
   Must include: model state dict, optimizer state dict, epoch, validation loss

3. `/app/output/summary.txt` - Training summary
   Must include lines with key-value pairs:
   ```
   validation_accuracy: 0.845
   total_training_time: 125.6
   epochs_trained: 28
   lr_reductions: 3
   early_stopping_triggered: True
   ```

## Constraints

- Maximum memory usage: 2GB
- Maximum runtime: 5 minutes
- Must handle class imbalance without special loss weighting
- No external libraries beyond those in the Docker environment

## Evaluation Criteria

The tests will verify:
1. Correct implementation of gradient accumulation
2. Proper gradient norm clipping
3. Adaptive learning rate schedule
4. Early stopping behavior
5. Correct metric logging
6. Model checkpoint integrity