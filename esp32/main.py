import network
import urequests
import time
import dht
import ujson
from machine import Pin, UART
from micropython import const

# Constants and Pin Assignments
ssid = "SIASICO"
password = "Waykokabalo0831"

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

# UART and Modbus setup
rs485_uart = UART(2, baudrate=4800, bits=8, parity=None, stop=1, tx=RS485_UART_TX, rx=RS485_UART_RX, timeout=200)
rs485_enable_pin = Pin(RS485_DE_RE_PIN, Pin.OUT)

# CORRECTED IMPORT: Assuming you have manually copied the umodbus file
import umodbus as ModbusRTUMaster

# Instantiate Modbus Master
modbus = ModbusRTUMaster.Serial(rs485_uart, rs485_enable_pin)

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
        # Note: The function call might change depending on the library's specifics.
        # This one is a common standard.
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
while True:
    try:
        sta = connect_wifi()

        sensor = dht.DHT11(Pin(DHT11_PIN_NUM))
        rain_pin = Pin(RAIN_PIN_NUM, Pin.IN, Pin.PULL_UP)
        rain_pin.irq(trigger=Pin.IRQ_FALLING, handler=rain_tip_handler)

        url = "https://bccweather-629d88a334c9.herokuapp.com/api/data/"

        while True:
            try:
                # Read DHT11 sensor
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
                    time.sleep(600)
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

                headers = {"Content-Type": "application/json"}
                response = urequests.post(url, data=ujson.dumps(payload), headers=headers)
                print("Server response:", response.text)
                response.close()

            except Exception as e:
                print("Error during sensor reading or HTTP request:", e)
                if not sta.isconnected():
                    print("WiFi disconnected, attempting to reconnect...")
                    break  # break inner loop to reconnect WiFi

            time.sleep(600)  # 10 minutes

    except OSError as e:
        print("Fatal error:", e)
        print("Retrying WiFi connection in 5 seconds...")
        time.sleep(5)