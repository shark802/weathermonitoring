import pandas as pd
import numpy as np
import joblib
import torch
import torch.nn as nn
import torch.optim as optim
from sklearn.preprocessing import StandardScaler
import onnx

# ======================
# 1. Load your dataset
# ======================
try:
    df = pd.read_csv("rainfall_dataset.csv")
    print("✅ Dataset 'rainfall_dataset.csv' loaded successfully.")
except FileNotFoundError:
    print("Error: 'rainfall_datasets.csv' not found. Please make sure the file is in the same directory.")
    exit()

FEATURE_COLS = ["temp", "humidity", "pressure", "wind_speed", "rain_mm"]
TARGET_COLS = ["rain_mm", "duration_min"]

# Check if required columns exist in the dataframe
if not all(col in df.columns for col in FEATURE_COLS + TARGET_COLS):
    print("Error: The CSV file is missing one or more required columns.")
    print(f"Required columns: {FEATURE_COLS + TARGET_COLS}")
    exit()

X = df[FEATURE_COLS].values
y = df[TARGET_COLS].values

# ======================
# 2. Scale data
# ======================
scaler_X = StandardScaler()
scaler_Y = StandardScaler()

X_scaled = scaler_X.fit_transform(X)
y_scaled = scaler_Y.fit_transform(y)

# ======================
# 3. Sequence the data (LSTM needs time steps)
# ======================
PAST_STEPS = 6

X_seq = []
y_seq = []
for i in range(PAST_STEPS, len(X_scaled)):
    X_seq.append(X_scaled[i-PAST_STEPS:i])
    y_seq.append(y_scaled[i])

# Ensure there's enough data to create sequences
if not X_seq:
    print("Error: Not enough data in the dataset to create sequences (PAST_STEPS is too large).")
    exit()

X_seq, y_seq = np.array(X_seq), np.array(y_seq)

# Convert numpy arrays to PyTorch tensors
X_tensor = torch.from_numpy(X_seq).float()
y_tensor = torch.from_numpy(y_seq).float()

# ======================
# 4. Build the model (using PyTorch's nn.Module)
# ======================
class LSTMModel(nn.Module):
    def __init__(self, input_dim, hidden_dim, output_dim, num_layers=1, dropout_rate=0.2):
        super(LSTMModel, self).__init__()
        self.lstm1 = nn.LSTM(input_dim, hidden_dim, num_layers=num_layers, batch_first=True, dropout=dropout_rate, bidirectional=False)
        self.lstm2 = nn.LSTM(hidden_dim, hidden_dim // 2, num_layers=num_layers, batch_first=True, bidirectional=False)
        self.fc = nn.Linear(hidden_dim // 2, output_dim)
        
    def forward(self, x):
        lstm_out1, _ = self.lstm1(x)
        lstm_out2, _ = self.lstm2(lstm_out1[:, -1:, :]) # We only take the last sequence from the output
        output = self.fc(lstm_out2.squeeze(1))
        return output

input_dim = len(FEATURE_COLS)
output_dim = len(TARGET_COLS)
hidden_dim = 64
num_layers = 1
dropout_rate = 0.2

model = LSTMModel(input_dim, hidden_dim, output_dim, num_layers, dropout_rate)
loss_function = nn.MSELoss()
optimizer = optim.Adam(model.parameters(), lr=0.001)

# ======================
# 5. Train the model
# ======================
print("\nStarting model training...")
epochs = 20
for epoch in range(epochs):
    # Forward pass
    predictions = model(X_tensor)
    loss = loss_function(predictions, y_tensor)

    # Backward and optimize
    optimizer.zero_grad()
    loss.backward()
    optimizer.step()

    if (epoch + 1) % 5 == 0:
        print(f'Epoch [{epoch+1}/{epochs}], Loss: {loss.item():.4f}')

print("Model training complete.")

# ======================
# 6. Save PyTorch model + scalers
# ======================
torch.save(model.state_dict(), "rain_model.pth")
joblib.dump(scaler_X, "scaler_X.pkl")
joblib.dump(scaler_Y, "scaler_y.pkl")

print("\n✅ PyTorch model (.pth) and scalers (.pkl) saved successfully!")

# ======================
# 7. Convert to ONNX format
# ======================
print("\nConverting PyTorch model to ONNX format...")

# Define a sample input with a dummy batch size of 1
dummy_input = torch.randn(1, PAST_STEPS, len(FEATURE_COLS))

# Export the model to ONNX
torch.onnx.export(
    model,
    dummy_input,
    "rain_model.onnx",
    verbose=True,
    input_names=['input'],
    output_names=['output'],
    dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}
)

print("✅ ONNX model (.onnx) saved successfully!")
