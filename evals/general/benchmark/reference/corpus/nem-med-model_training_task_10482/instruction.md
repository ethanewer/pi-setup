## Custom Training Loop with Gradient Accumulation and Learning Rate Scheduling

You are implementing a training system for a binary classification model that must handle large batches through gradient accumulation while using sophisticated learning rate scheduling. The system must train for a fixed number of epochs and evaluate performance at regular intervals.

## Your Task

1. **Implement Gradient Accumulation Training Loop**
   - Create a training function that accumulates gradients over multiple mini-batches before performing an optimizer step
   - For every `accumulation_steps` mini-batches, average the accumulated gradients and update model weights
   - Track and report loss per accumulation step, not per mini-batch
   - Handle the final accumulation step correctly if the total batches aren't divisible by accumulation steps

2. **Implement Composite Learning Rate Scheduler**
   - Create a scheduler that combines two policies:
     - Warmup: Linear warmup from 0 to base learning rate over first `warmup_epochs`
     - Cosine Annealing: After warmup, use cosine annealing to gradually reduce learning rate
   - Formula: 
     - Warmup: `lr = base_lr * (current_epoch / warmup_epochs)`
     - Cosine: `lr = base_lr * 0.5 * (1 + cos(π * (current_epoch - warmup_epochs) / (total_epochs - warmup_epochs)))`
   - The scheduler should update at the end of each epoch

3. **Implement Early Stopping with Patience**
   - Monitor validation loss and stop training if it doesn't improve for `patience` epochs
   - Save the model checkpoint whenever validation loss improves
   - Restore the best model weights after early stopping

4. **Training and Evaluation Pipeline**
   - Load the dataset from `/app/data/train.csv` and `/app/data/val.csv`
   - Create a simple neural network: 3 linear layers (input_size → 64 → 32 → 1) with ReLU activation
   - Use binary cross-entropy loss with sigmoid activation
   - Train for `max_epochs` epochs with the configured hyperparameters
   - Evaluate on validation set every epoch, compute accuracy and loss

5. **Save Results and Artifacts**
   - Save the best model to `/app/output/best_model.pth`
   - Save training history to `/app/output/training_history.json` with:
     - Per-epoch: `epoch`, `train_loss`, `val_loss`, `val_accuracy`, `learning_rate`
     - Per-accumulation-step: `step_loss` (for the last epoch only)
   - Save final configuration to `/app/output/config_summary.json` with all hyperparameters

## Expected Outputs

- `/app/output/best_model.pth`: PyTorch model state dict
- `/app/output/training_history.json`: JSON file with training metrics
- `/app/output/config_summary.json`: JSON file with hyperparameters used

## Configuration

Use the following hyperparameters (read from `/app/config/hyperparameters.json`):
- `batch_size`: 32
- `accumulation_steps`: 4
- `base_learning_rate`: 0.001
- `warmup_epochs`: 3
- `total_epochs`: 20
- `patience`: 5
- `input_size`: 10
- `seed`: 42

## Dataset Format

Training and validation CSVs have:
- 10 feature columns (f1-f10): float values
- 1 target column (target): 0 or 1

## Success Criteria

1. Training history file contains correct metrics for all epochs
2. Model checkpoint loads successfully and can make predictions
3. Learning rate follows the specified warmup + cosine schedule
4. Early stopping works correctly when validation loss plateaus
5. Gradient accumulation properly handles batch normalization statistics