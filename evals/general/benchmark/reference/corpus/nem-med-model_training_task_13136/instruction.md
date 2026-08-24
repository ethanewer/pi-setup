# Learning Rate Scheduling with Gradient Accumulation

## Context
You are training a language model on a resource-constrained environment. To handle large effective batch sizes while managing memory usage, you need to implement gradient accumulation combined with learning rate scheduling. This is crucial for stable training when using large models or limited GPU memory.

## Your Task
Implement a training loop with gradient accumulation and cosine annealing learning rate scheduling for a text classification model.

### 1. Data Loading and Preparation
- Load the dataset from `/app/data/train.csv` and `/app/data/val.csv`
- Each CSV has columns: `text` (string) and `label` (integer 0-3)
- Create PyTorch DataLoaders with:
  - Batch size: 8 (per forward pass)
  - Effective batch size: 32 (after accumulation)
  - Shuffle training data only
  - No data augmentation required

### 2. Model Setup
Use the provided model class (already imported). The model has:
- Input dimension: 768 (pretrained embeddings)
- Hidden layers: [768, 512, 256]
- Output: 4 classes
- Dropout: 0.3
- Initialize model with random weights (no pretrained weights)

### 3. Gradient Accumulation Implementation
Implement gradient accumulation with these requirements:
- Accumulate gradients over `accumulation_steps = 4` batches
- Only update model weights after accumulating `accumulation_steps` batches
- Clear gradients after each weight update (not after each batch)
- Handle partial accumulation steps at the end of each epoch
- Print gradient norm after each accumulation step for monitoring

### 4. Cosine Annealing Learning Rate Scheduler
Implement cosine annealing with warm restarts:
- Initial learning rate: 1e-3
- Minimum learning rate: 1e-5
- T_0: 5 epochs (period for first restart)
- T_mult: 2 (multiply period by 2 after each restart)
- Warm restarts after each period
- Update learning rate after each weight update (not after each batch)

### 5. Training Loop
Implement a complete training loop with:
- 15 total epochs
- Loss function: CrossEntropyLoss
- Optimizer: AdamW with weight decay 0.01
- Gradient clipping: clip gradient norm to 1.0
- Track and log:
  - Training loss (per accumulation step)
  - Training accuracy (per epoch)
  - Validation loss (per epoch)
  - Validation accuracy (per epoch)
  - Current learning rate (per weight update)

### 6. Checkpointing
- Save the best model based on validation accuracy to `/app/output/best_model.pt`
- Save the final model after 15 epochs to `/app/output/final_model.pt`
- Save training history to `/app/output/training_history.json` with format:
  ```json
  {
    "epochs": [
      {
        "epoch": 1,
        "train_loss": [0.5, 0.48, ...],  // per accumulation step
        "train_accuracy": 0.65,
        "val_loss": 0.52,
        "val_accuracy": 0.62,
        "learning_rates": [0.001, 0.0009, ...]  // per weight update
      },
      ...
    ],
    "best_epoch": 8,
    "best_val_accuracy": 0.78
  }
  ```

## Expected Outputs
- `/app/output/best_model.pt`: PyTorch model state dict of best model
- `/app/output/final_model.pt`: PyTorch model state dict of final model  
- `/app/output/training_history.json`: JSON file with training history as specified above

## Success Criteria
1. Model trains for exactly 15 epochs
2. Gradient accumulation correctly accumulates over 4 batches before updates
3. Learning rate follows cosine annealing with warm restarts pattern
4. Training history file contains accurate loss and accuracy values
5. Best model is saved based on validation accuracy
6. Gradient clipping prevents gradient explosion