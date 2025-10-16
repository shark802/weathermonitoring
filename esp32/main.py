import network
import urequests
import time
import dht
import ujson
from machine import Pin, UART
from micropython import const

# ----------------------------------------------------------------------
# 1. Configuration Constants and Pin Assignments
# ----------------------------------------------------------------------
ssid = "CB5 Lab WiFi"
password = "cb5@bcc2025"

# DHT11 Sensor Pin
DHT11_PIN_NUM = 4 # Connects to the DHT11 data pin

# Rain Gauge Pin and variables
RAIN_PIN_NUM = 5 
rain_tip_count = 0
last_tip_time = 0
RAIN_TIP_DEBOUNCE_MS = const(200) # Debounce time for rain gauge tip

# Wind Speed Pulse Input
WIND_SPEED_PIN = 21 # GPIO21 for ZTS-3000 Wind Speed Pulse (Blue/White wire)
wind_pulse_count = 0
# Calibration factor: Wind Speed (m/s) = Frequency (Hz) * FACTOR
# **CHECK YOUR ZTS-3000 MANUAL FOR THE CORRECT FACTOR**
WIND_SPEED_FACTOR = 0.5 

# RS485 Modbus (ZTS-3000 Wind Direction) Pins
RS485_UART_TX = 17 # GPIO17 -> RS485 Module DI
RS485_UART_RX = 16 # GPIO16 <- Logic Level Shifter <- RS485 Module RO
RS485_DE_RE_PIN = 18 # GPIO18 -> RS485 Module RE/DE (tied)

# Modbus Sensor Address
WIND_SENSOR_ADDR = 0x01

# Modbus Register Address (for Wind Direction)
WIND_DIRECTION_REG = 0x0001
WIND_DIRECTION_SCALING = 10.0 # Standard ZTS-3000 scaling for 0.1 degree resolution

INTERVAL_SECONDS = 600 # Data collection interval: 10 minutes

# ----------------------------------------------------------------------
# 2. Pin Setup and Communication Initialization
# ----------------------------------------------------------------------

# 2.1 Interrupt Pin Setup
rain_pin = Pin(RAIN_PIN_NUM, Pin.IN, Pin.PULL_UP)
wind_speed_pin = Pin(WIND_SPEED_PIN, Pin.IN, Pin.PULL_UP)

# 2.2 RS485 Modbus Initialization
# The ctrl_pin handles the DE/RE direction switching automatically by umodbus
modbus = ModbusRTUMaster(
    uart_id=2, 
    baudrate=4800, 
    pins=[RS485_UART_TX, RS485_UART_RX], 
    ctrl_pin=RS485_DE_RE_PIN
)

# ----------------------------------------------------------------------
# 3. Interrupt Handlers
# ----------------------------------------------------------------------

# Interrupt handler for rain gauge
def rain_tip_handler(pin):
    global rain_tip_count, last_tip_time
    current_time = time.ticks_ms()
    # Debounce check
    if time.ticks_diff(current_time, last_tip_time) > RAIN_TIP_DEBOUNCE_MS: 
        rain_tip_count += 1
        last_tip_time = current_time

# Interrupt handler for wind speed sensor (Pulse Counter)
def wind_pulse_handler(pin):
    global wind_pulse_count
    # The wind pulse signal is often a clean square wave; debouncing may not be needed
    # but could be added if noise is observed.
    wind_pulse_count += 1

# Attach Interrupts
rain_pin.irq(trigger=Pin.IRQ_FALLING, handler=rain_tip_handler)
wind_speed_pin.irq(trigger=Pin.IRQ_RISING, handler=wind_pulse_handler)

# ----------------------------------------------------------------------
# 4. Core Functions
# ----------------------------------------------------------------------

# WiFi connection function
def connect_wifi():
    sta = network.WLAN(network.STA_IF)
    if not sta.active():
        sta.active(True)

    if not sta.isconnected():
        print("Connecting to WiFi...")
        sta.connect(ssid, password)

        max_wait = 10
        while max_wait > 0:
            if sta.isconnected():
                break
            max_wait -= 1
            print('waiting...')
            time.sleep(1)

    if not sta.isconnected():
        raise OSError("Failed to connect to WiFi")

    print("WiFi connected. IP:", sta.ifconfig()[0])
    return sta

# Function to read Modbus Wind Direction
def read_modbus_direction():
    wind_direction = -1.0
    
    try:
        # Read a single holding register (0x0001) from the sensor address (0x01)
        response_dir = modbus.read_holding_registers(WIND_SENSOR_ADDR, WIND_DIRECTION_REG, 1)
        if response_dir:
            # Scale the raw integer value (e.g., raw 1800 -> 180.0 degrees)
            wind_direction = response_dir[0] / WIND_DIRECTION_SCALING
            print("Wind Direction:", wind_direction, "degrees")
    except Exception as e:
        print("Error reading wind direction via Modbus:", e)

    return wind_direction

# Function to calculate wind speed from pulse count
def calculate_wind_speed():
    global wind_pulse_count
    
    # 1. Safely get and reset the pulse count
    pulses = wind_pulse_count
    wind_pulse_count = 0
    
    # 2. Calculate Frequency (Hz = pulses / time in seconds)
    # The time interval is the main loop's logging interval (600 seconds)
    frequency_hz = pulses / INTERVAL_SECONDS
    
    # 3. Calculate Speed (m/s)
    wind_speed = frequency_hz * WIND_SPEED_FACTOR 
    
    print(f"Wind Pulses: {pulses}, Freq: {frequency_hz:.2f} Hz, Speed: {wind_speed:.2f} m/s")
    
    return wind_speed

# ----------------------------------------------------------------------
# 5. Main Execution Loop
# ----------------------------------------------------------------------
last_run_time = 0

while True:
    try:
        # Check if the data collection interval has passed
        if time.time() - last_run_time >= INTERVAL_SECONDS:
            print("\n--- Starting new data collection cycle ---")
            
            # --- WiFi Connection ---
            sta = connect_wifi()

            # --- Read DHT11 sensor ---
            temp = -1
            hum = -1
            sensor = dht.DHT11(Pin(DHT11_PIN_NUM))
            for attempt in range(2):
                try:
                    sensor.measure()
                    temp = sensor.temperature()
                    hum = sensor.humidity()
                    print(f"DHT11: Temp={temp}°C, Hum={hum}%")
                    break
                except Exception as e:
                    print(f"DHT11 read attempt {attempt + 1} failed:", e)
                    time.sleep(1)
            else:
                print("Failed to read DHT11, using default values.")

            # --- Read Wind Direction (Modbus) ---
            wind_direction = read_modbus_direction()

            # --- Calculate Wind Speed (Pulse Counter) ---
            wind_speed = calculate_wind_speed()

            # --- Read and Reset Rainfall ---
            tips = rain_tip_count
            rain_tip_count = 0
            # Assuming 1 tip = 0.3mm (Adjust as needed)
            rainfall_mm = tips * 0.3
            print(f"Rainfall: {rainfall_mm:.1f} mm ({tips} tips)")

            # --- Prepare and Send Data ---
            payload = {
                "temperature": temp,
                "humidity": hum,
                "rainfall_mm": rainfall_mm,
                "rain_tip_count": tips,
                "wind_speed": wind_speed,
                "wind_direction": wind_direction,
                "sensor_id": 1
            }

            url = "https://bccweatherapp-8fcc2a32c70f.herokuapp.com/api/data/"
            headers = {"Content-Type": "application/json"}
            
            response = urequests.post(url, data=ujson.dumps(payload), headers=headers)
            print(f"Server response: Status {response.status_code}")
            # print("Response text:", response.text) # Uncomment for debug
            response.close()

            # Update the last run time
            last_run_time = time.time()
            
    except OSError as e:
        print("Fatal OSError (e.g., WiFi or Network issue):", e)
        print("Retrying in 10 seconds...")
        time.sleep(10)
    
    except Exception as e:
        print("An unexpected error occurred:", e)
        print("Retrying in 10 seconds...")
        time.sleep(10)

    # Short sleep to prevent immediate re-check and yield control to the OS
    time.sleep(5)