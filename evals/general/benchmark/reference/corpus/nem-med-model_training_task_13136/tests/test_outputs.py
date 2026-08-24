import os
import json
import torch
import numpy as np
import pandas as pd
from pathlib import Path

def test_output_files_exist():
    """Verify all required output files were created."""
    assert os.path.exists('/app/output/best_model.pt'), "Best model file missing"
    assert os.path.exists('/app/output/final_model.pt'), "Final model file missing"
    assert os.path.exists('/app/output/training_history.json'), "Training history file missing"

def test_training_history_format():
    """Verify training history has correct structure."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    # Check top-level structure
    assert 'epochs' in history, "Missing 'epochs' key"
    assert 'best_epoch' in history, "Missing 'best_epoch' key"
    assert 'best_val_accuracy' in history, "Missing 'best_val_accuracy' key"
    
    # Check epochs array
    epochs = history['epochs']
    assert len(epochs) == 15, f"Expected 15 epochs, got {len(epochs)}"
    
    # Check first epoch structure
    epoch1 = epochs[0]
    required_keys = ['epoch', 'train_loss', 'train_accuracy', 'val_loss', 'val_accuracy', 'learning_rates']
    for key in required_keys:
        assert key in epoch1, f"Missing key '{key}' in epoch data"
    
    # Check data types
    assert isinstance(epoch1['train_loss'], list), "train_loss should be list"
    assert isinstance(epoch1['learning_rates'], list), "learning_rates should be list"
    assert isinstance(epoch1['train_accuracy'], (int, float)), "train_accuracy should be numeric"
    assert isinstance(epoch1['val_accuracy'], (int, float)), "val_accuracy should be numeric"

def test_model_checkpoints():
    """Verify model checkpoints can be loaded and have correct architecture."""
    # Load the provided model class
    import sys
    sys.path.append('/app')
    from model import TextClassifier
    
    # Test loading best model
    best_model = TextClassifier()
    best_state = torch.load('/app/output/best_model.pt', map_location='cpu')
    best_model.load_state_dict(best_state)
    
    # Test loading final model
    final_model = TextClassifier()
    final_state = torch.load('/app/output/final_model.pt', map_location='cpu')
    final_model.load_state_dict(final_state)
    
    # Verify model can make predictions
    test_input = torch.randn(2, 768)  # batch_size=2, input_dim=768
    best_output = best_model(test_input)
    final_output = final_model(test_input)
    
    assert best_output.shape == (2, 4), f"Best model output shape incorrect: {best_output.shape}"
    assert final_output.shape == (2, 4), f"Final model output shape incorrect: {final_output.shape}"

def test_training_progress():
    """Verify training shows improvement and learning rate scheduling works."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    epochs = history['epochs']
    
    # Check learning rate scheduling
    lr_pattern_valid = False
    for epoch in epochs:
        lrs = epoch['learning_rates']
        if len(lrs) > 1:
            # Learning rates should generally decrease within a period
            # but may reset with warm restarts
            decreasing = all(lrs[i] >= lrs[i+1] for i in range(len(lrs)-1))
            if not decreasing:
                # If not decreasing, check if it's a restart (lr increases)
                # This is a simplified check
                lr_pattern_valid = True
                break
    
    # Check for training improvement
    first_val_acc = epochs[0]['val_accuracy']
    best_val_acc = history['best_val_accuracy']
    assert best_val_acc >= first_val_acc, "Model should improve from initial performance"
    assert best_val_acc > 0.1, "Validation accuracy too low, training may have failed"

def test_gradient_accumulation_logic():
    """Verify gradient accumulation steps match expected pattern."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    # Load training data to calculate expected steps
    train_df = pd.read_csv('/app/data/train.csv')
    batch_size = 8
    accumulation_steps = 4
    samples_per_epoch = len(train_df)
    
    # Calculate expected weight updates per epoch
    batches_per_epoch = (samples_per_epoch + batch_size - 1) // batch_size
    weight_updates_per_epoch = (batches_per_epoch + accumulation_steps - 1) // accumulation_steps
    
    # Check first epoch
    epoch1 = history['epochs'][0]
    train_losses = epoch1['train_loss']
    learning_rates = epoch1['learning_rates']
    
    # Number of weight updates should match
    assert len(learning_rates) == weight_updates_per_epoch, \
        f"Expected {weight_updates_per_epoch} weight updates, got {len(learning_rates)}"
    
    # Train losses should match accumulation steps
    assert len(train_losses) == batches_per_epoch, \
        f"Expected {batches_per_epoch} loss values (one per batch), got {len(train_losses)}"

def test_data_loading():
    """Verify data was loaded correctly."""
    # This test ensures the agent properly read the input files
    train_path = '/app/data/train.csv'
    val_path = '/app/data/val.csv'
    
    assert os.path.exists(train_path), f"Training data missing: {train_path}"
    assert os.path.exists(val_path), f"Validation data missing: {val_path}"
    
    train_df = pd.read_csv(train_path)
    val_df = pd.read_csv(val_path)
    
    assert 'text' in train_df.columns, "Missing 'text' column in training data"
    assert 'label' in train_df.columns, "Missing 'label' column in training data"
    assert 'text' in val_df.columns, "Missing 'text' column in validation data"
    assert 'label' in val_df.columns, "Missing 'label' column in validation data"
    
    # Check label range
    assert train_df['label'].min() >= 0, "Labels should be >= 0"
    assert train_df['label'].max() <= 3, "Labels should be <= 3"
    assert val_df['label'].min() >= 0, "Labels should be >= 0"
    assert val_df['label'].max() <= 3, "Labels should be <= 3"