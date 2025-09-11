import pandas as pd
import numpy as np
import joblib
from sklearn.preprocessing import StandardScaler
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout

# ======================
# 1. Load your dataset
# ======================
df = pd.read_csv("rainfall_dataset.csv")

FEATURE_COLS = ["temp", "humidity", "pressure", "wind_speed", "rain_mm"]
TARGET_COLS = ["rain_mm", "duration_min"]

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

X_seq, y_seq = np.array(X_seq), np.array(y_seq)

# ======================
# 4. Build the model
# ======================
model = Sequential([
    LSTM(64, input_shape=(PAST_STEPS, len(FEATURE_COLS)), return_sequences=True),
    Dropout(0.2),
    LSTM(32),
    Dense(len(TARGET_COLS))
])

# Use full loss name for compatibility
model.compile(optimizer="adam", loss="mean_squared_error")

# ======================
# 5. Train
# ======================
history = model.fit(X_seq, y_seq, epochs=20, batch_size=32, validation_split=0.2)

# ======================
# 6. Save model + scalers
# ======================
model.save("rain_model.h5")
joblib.dump(scaler_X, "scaler_X.pkl")
joblib.dump(scaler_Y, "scaler_y.pkl")

print("✅ Model and scalers saved successfully!")
