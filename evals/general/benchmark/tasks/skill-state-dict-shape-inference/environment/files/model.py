import torch

class Net(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = torch.nn.Linear(3, 4)   # in_features=3, out_features=4
        self.fc2 = torch.nn.Linear(4, 2)   # in_features=4, out_features=2

    def forward(self, x):
        x = torch.relu(self.fc1(x))
        return self.fc2(x)