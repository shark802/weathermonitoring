import network
import urequests
import time
import dht
import ujson
from machine import Pin, UART
from micropython import const

# Constants and Pin Assignments
ssid = "CB5 Lab WiFi"
password = "cb5@bcc2025"

# DHT11 Sensor Pin
DHT11_PIN_NUM = 4

# Rain Gauge Pin and variables
RAIN_PIN_NUM = 5
rain_tip_count = 0
last_tip_time = 0

# RS485 Modbus Pins
RS485_UART_TX = 17  # GPIO17
RS485_UART_RX = 16  # GPIO16
RS485_DE_RE_PIN = 18 # GPIO18

# Modbus Sensor Addresses
WIND_SPEED_ADDR = 0x01
WIND_DIRECTION_ADDR = 0x02

# Modbus Register Addresses (from sensor datasheet)
WIND_SPEED_REG = 0x0001
WIND_DIRECTION_REG = 0x0001

# Corrected UART and Modbus setup
rs485_enable_pin = Pin(RS485_DE_RE_PIN, Pin.OUT)
# Assuming ModbusRTUMaster is correctly imported from umodbus.serial
from umodbus.serial import Serial as ModbusRTUMaster
modbus = ModbusRTUMaster(uart_id=2, baudrate=4800, pins=[RS485_UART_TX, RS485_UART_RX], ctrl_pin=RS485_DE_RE_PIN)

# Interrupt handler for rain gauge
def rain_tip_handler(pin):
    global rain_tip_count, last_tip_time
    current_time = time.ticks_ms()
    if time.ticks_diff(current_time, last_tip_time) > 200:  # debounce 200 ms
        rain_tip_count += 1
        last_tip_time = current_time

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

# Function to read Modbus sensors
def read_modbus_sensors():
    wind_speed = -1.0
    wind_direction = -1.0
    
    # Read wind speed
    try:
        response_speed = modbus.read_holding_registers(WIND_SPEED_ADDR, WIND_SPEED_REG, 1)
        if response_speed:
            wind_speed = response_speed[0] / 100.0
            print("Wind Speed:", wind_speed, "m/s")
    except Exception as e:
        print("Error reading wind speed:", e)

    # Read wind direction
    try:
        response_dir = modbus.read_holding_registers(WIND_DIRECTION_ADDR, WIND_DIRECTION_REG, 1)
        if response_dir:
            wind_direction = response_dir[0] / 10.0
            print("Wind Direction:", wind_direction, "degrees")
    except Exception as e:
        print("Error reading wind direction:", e)

    return wind_speed, wind_direction

# Main loop
last_run_time = 0
INTERVAL_SECONDS = 600  # 10 minutes

while True:
    try:
        # Check if 10 minutes have passed
        if time.time() - last_run_time >= INTERVAL_SECONDS:
            print("--- Starting new data collection cycle ---")
            
            # Reconnect WiFi if needed
            sta = connect_wifi()

            # Read DHT11 sensor
            sensor = dht.DHT11(Pin(DHT11_PIN_NUM))
            for attempt in range(2):
                try:
                    sensor.measure()
                    temp = sensor.temperature()
                    hum = sensor.humidity()
                    break
                except Exception as e:
                    print(f"DHT11 read attempt {attempt + 1} failed:", e)
                    time.sleep(1)
            else:
                print("Failed to read DHT11 after 2 attempts, skipping this cycle")
                last_run_time = time.time()
                continue

            # Read wind sensors
            wind_speed, wind_direction = read_modbus_sensors()

            # Safely read and reset rain tip count
            tips = rain_tip_count
            rain_tip_count = 0
            rainfall_mm = tips * 0.3

            payload = {
                "temperature": temp,
                "humidity": hum,
                "rainfall_mm": rainfall_mm,
                "rain_tip_count": tips,
                "wind_speed": wind_speed,
                "wind_direction": wind_direction,
                "sensor_id": 1
            }

            url = "https://bccweatherapp-8fcc2a32c70f.herokuapp.com//api/data/"
            headers = {"Content-Type": "application/json"}
            
            response = urequests.post(url, data=ujson.dumps(payload), headers=headers)
            print("Server response:", response.text)
            response.close()

            # Update the last run time
            last_run_time = time.time()
            
    except OSError as e:
        print("Fatal error:", e)
        print("Retrying in 5 seconds...")
        time.sleep(5)
    
    except Exception as e:
        print("An unexpected error occurred:", e)
        print("Retrying in 5 seconds...")
        time.sleep(5)

    # Add a short sleep to yield control
    time.sleep(5)