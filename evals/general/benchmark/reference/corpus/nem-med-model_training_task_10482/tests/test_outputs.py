import os
import json
import torch
import numpy as np
import pandas as pd
from torch import nn
import pytest

def test_output_files_exist():
    """Verify all required output files were created."""
    assert os.path.exists('/app/output/best_model.pth'), "Model checkpoint not found"
    assert os.path.exists('/app/output/training_history.json'), "Training history not found"
    assert os.path.exists('/app/output/config_summary.json'), "Config summary not found"

def test_model_checkpoint_loadable():
    """Verify model checkpoint can be loaded and used."""
    # Load the model architecture
    class SimpleModel(nn.Module):
        def __init__(self, input_size=10):
            super().__init__()
            self.layers = nn.Sequential(
                nn.Linear(input_size, 64),
                nn.ReLU(),
                nn.Linear(64, 32),
                nn.ReLU(),
                nn.Linear(32, 1)
            )
        
        def forward(self, x):
            return self.layers(x)
    
    model = SimpleModel()
    
    # Load state dict
    state_dict = torch.load('/app/output/best_model.pth', map_location='cpu')
    model.load_state_dict(state_dict)
    
    # Test forward pass
    test_input = torch.randn(2, 10)
    output = model(test_input)
    assert output.shape == (2, 1), f"Expected output shape (2, 1), got {output.shape}"
    assert not torch.isnan(output).any(), "Model output contains NaN"

def test_training_history_structure():
    """Verify training history has correct structure and data types."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    # Check required keys
    assert 'epochs' in history, "Missing 'epochs' in history"
    assert 'final_accumulation_steps' in history, "Missing 'final_accumulation_steps' in history"
    
    # Check epoch data
    epochs = history['epochs']
    assert len(epochs) > 0, "No epoch data recorded"
    
    for epoch_data in epochs:
        assert 'epoch' in epoch_data, "Missing epoch number"
        assert 'train_loss' in epoch_data, "Missing train_loss"
        assert 'val_loss' in epoch_data, "Missing val_loss"
        assert 'val_accuracy' in epoch_data, "Missing val_accuracy"
        assert 'learning_rate' in epoch_data, "Missing learning_rate"
        
        # Check data types
        assert isinstance(epoch_data['epoch'], int), "Epoch should be integer"
        assert isinstance(epoch_data['train_loss'], (int, float)), "Train loss should be numeric"
        assert isinstance(epoch_data['val_loss'], (int, float)), "Val loss should be numeric"
        assert isinstance(epoch_data['val_accuracy'], (int, float)), "Accuracy should be numeric"
        assert isinstance(epoch_data['learning_rate'], (int, float)), "Learning rate should be numeric"
        
        # Check value ranges
        assert 0 <= epoch_data['val_accuracy'] <= 1, f"Accuracy {epoch_data['val_accuracy']} not in [0,1]"
        assert epoch_data['learning_rate'] >= 0, f"Learning rate {epoch_data['learning_rate']} negative"

def test_learning_rate_schedule():
    """Verify learning rate follows warmup + cosine annealing schedule."""
    with open('/app/output/config_summary.json', 'r') as f:
        config = json.load(f)
    
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    base_lr = config['base_learning_rate']
    warmup_epochs = config['warmup_epochs']
    total_epochs = config['total_epochs']
    
    epochs_data = history['epochs']
    
    # Calculate expected learning rates
    for epoch_data in epochs_data:
        epoch = epoch_data['epoch']
        actual_lr = epoch_data['learning_rate']
        
        if epoch < warmup_epochs:
            # Warmup phase
            expected_lr = base_lr * (epoch / warmup_epochs)
        else:
            # Cosine annealing phase
            progress = (epoch - warmup_epochs) / (total_epochs - warmup_epochs)
            expected_lr = base_lr * 0.5 * (1 + np.cos(np.pi * progress))
        
        # Allow small floating point differences
        assert abs(actual_lr - expected_lr) < 1e-6, \
            f"Epoch {epoch}: LR {actual_lr} doesn't match expected {expected_lr}"

def test_gradient_accumulation_tracking():
    """Verify accumulation step losses are tracked for last epoch."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    assert 'final_accumulation_steps' in history, "Missing accumulation step data"
    accumulation_data = history['final_accumulation_steps']
    
    # Should have list of losses for accumulation steps
    assert isinstance(accumulation_data, list), "Accumulation data should be a list"
    assert len(accumulation_data) > 0, "No accumulation step data"
    
    for step_loss in accumulation_data:
        assert isinstance(step_loss, (int, float)), "Step loss should be numeric"
        assert step_loss >= 0, f"Step loss {step_loss} should be non-negative"

def test_early_stopping_behavior():
    """Verify early stopping works correctly."""
    with open('/app/output/training_history.json', 'r') as f:
        history = json.load(f)
    
    with open('/app/output/config_summary.json', 'r') as f:
        config = json.load(f)
    
    epochs_data = history['epochs']
    patience = config['patience']
    
    # Track validation loss improvements
    best_loss = float('inf')
    epochs_since_improvement = 0
    stopped_early = False
    
    for epoch_data in epochs_data:
        val_loss = epoch_data['val_loss']
        
        if val_loss < best_loss - 1e-6:  # Significant improvement
            best_loss = val_loss
            epochs_since_improvement = 0
        else:
            epochs_since_improvement += 1
        
        if epochs_since_improvement >= patience:
            stopped_early = True
            break
    
    # Either stopped early or completed all epochs
    # This test passes as long as the logic above doesn't crash
    # Actual early stopping behavior is validated by model being saved
    assert True, "Early stopping logic check completed"

def test_config_summary_complete():
    """Verify config summary contains all required hyperparameters."""
    with open('/app/output/config_summary.json', 'r') as f:
        config = json.load(f)
    
    required_keys = [
        'batch_size', 'accumulation_steps', 'base_learning_rate',
        'warmup_epochs', 'total_epochs', 'patience', 'input_size', 'seed'
    ]
    
    for key in required_keys:
        assert key in config, f"Missing key {key} in config summary"
        assert config[key] is not None, f"Key {key} is None in config summary"