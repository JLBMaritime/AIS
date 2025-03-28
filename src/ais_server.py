#!/usr/bin/env python3
import serial
import socket
import threading
import configparser
import time
import logging
import sys
import signal

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")

# Load configuration from .conf file
def load_config(file_path):
    config = configparser.ConfigParser()
    try:
        config.read(file_path)
        if not config.has_section("AIS"):
            raise ValueError("Missing 'AIS' section in config file")
        return config
    except Exception as e:
        logging.error(f"Error loading config file: {e}")
        sys.exit(1)

# Function to send data to a specific IP and port
def send_data(ip, port, data, max_retries=3):
    for attempt in range(max_retries):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(5)  # Set a timeout for the connection
                s.connect((ip, int(port)))
                s.sendall(data)
                logging.info(f"Data sent to {ip}:{port}")
                break  # Exit the retry loop on success
        except socket.error as e:
            logging.warning(f"Attempt {attempt + 1} failed to send data to {ip}:{port}: {e}")
            if attempt == max_retries - 1:
                logging.error(f"Failed to send data after {max_retries} attempts")
            time.sleep(2)  # Wait before retrying

# AIS data handling
def handle_ais(serial_port, ip, port):
    try:
        with serial.Serial(serial_port, baudrate=38400, timeout=2) as ser:
            logging.info(f"Connected to AIS serial port: {serial_port}")
            while True:
                try:
                    line = ser.readline()
                    if line:
                        logging.debug(f"Received AIS data: {line}")
                        send_data(ip, port, line)
                except serial.SerialException as e:
                    logging.error(f"AIS serial read error: {e}")
                    time.sleep(5)
    except Exception as e:
        logging.error(f"Error with AIS serial port: {e}")

# Signal handler for graceful shutdown
def signal_handler(sig, frame):
    logging.info("Shutting down gracefully...")
    sys.exit(0)

# Main function
def main():
    # Allow configuration file path to be passed as a command-line argument
    config_file = sys.argv[1] if len(sys.argv) > 1 else "/home/JLBMaritime/ais_project/ais_config.conf"
    config = load_config(config_file)

    ais_serial_port = config["AIS"]["serial_port"]
    ais_ip = config["AIS"]["ip"]
    ais_port = config["AIS"]["port"]

    # Set up signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)

    # Create and start thread for AIS
    ais_thread = threading.Thread(target=handle_ais, args=(ais_serial_port, ais_ip, ais_port), daemon=True)
    ais_thread.start()
    logging.info("AIS thread started")

    # Keep the main thread alive
    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
