# AIS Data Forwarding System for Raspberry Pi

This repository contains the necessary files and scripts to set up an AIS (Automatic Identification System) data forwarding system on a Raspberry Pi 4B with a dAISy HAT.

## Overview

This system reads AIS data from a dAISy HAT connected to a Raspberry Pi's serial port and forwards it to a specified IP address and port over TCP/IP. It's designed to run as a systemd service for reliability and automatic startup.

![AIS Data Flow](https://raw.githubusercontent.com/JLBMaritime/AIS/main/docs/ais_flow_diagram.png)

## Hardware Requirements

- Raspberry Pi 4B (2GB RAM recommended)
- dAISy HAT or compatible AIS receiver
- Micro SD card (8GB or larger)
- Power supply for Raspberry Pi
- Antenna suitable for AIS reception

## Software Requirements

- Raspberry Pi OS (64-bit, Lite version recommended)
- Python 3.7 or newer
- Required Python packages: pyserial

## Quick Installation

For a quick automated installation, run:

```bash
git clone https://github.com/JLBMaritime/AIS.git
cd AIS
chmod +x install.sh
sudo ./install.sh
```

## Manual Installation

Follow these steps for a manual installation:

### 1. Prepare the Raspberry Pi

1. Flash 64-bit Raspberry Pi OS (without desktop) to a micro-SD card using the Raspberry Pi Imager.
2. Insert the micro-SD card into the Raspberry Pi and power it on.
3. Update the system:
   ```bash
   sudo apt update
   sudo apt full-upgrade -y
   sudo reboot now
   ```

### 2. Enable Remote Connection (Optional)

1. Install Raspberry Pi Connect:
   ```bash
   sudo apt install rpi-connect-lite
   rpi-connect on
   loginctl enable-linger
   rpi-connect signin
   rpi-connect shell on
   ```
2. Complete sign-in by visiting the provided URL.

### 3. Configure the Serial Port

1. Run Raspberry Pi configuration:
   ```bash
   sudo raspi-config
   ```
2. Navigate to: 3 Interface Options → I6 Serial Port
3. Select "No" for login shell over serial
4. Select "Yes" to enable the serial port hardware
5. Select "Finish" and reboot if prompted

### 4. Install Required Software

1. Install screen (useful for debugging):
   ```bash
   sudo apt-get install screen -y
   ```
2. Install Python and pip:
   ```bash
   sudo apt install python3 python3-pip -y
   ```
3. Install virtualenv:
   ```bash
   sudo apt install python3-venv -y
   ```

### 5. Set Up the Project

1. Create a project directory:
   ```bash
   mkdir ~/ais_project
   cd ~/ais_project
   ```
2. Create a virtual environment:
   ```bash
   python3 -m venv ais_env
   ```
3. Activate the virtual environment:
   ```bash
   source ais_env/bin/activate
   ```
4. Install the required Python package:
   ```bash
   pip install pyserial
   ```
5. Deactivate the virtual environment:
   ```bash
   deactivate
   ```

### 6. Deploy Configuration Files

1. Create the configuration file:
   ```bash
   nano ~/ais_project/ais_config.conf
   ```
2. Add the following content (modify as needed):
   ```
   [AIS]
   serial_port = /dev/serial0
   # Replace with your actual serial port
   ip = 192.168.1.100
   # Replace with the target IP address
   port = 12345
   # Replace with the target port number
   ```
3. Create the Python script:
   ```bash
   nano ~/ais_project/ais_server.py
   ```
4. Copy the content from the `src/ais_server.py` file in this repository.
5. Make the script executable:
   ```bash
   chmod +x ~/ais_project/ais_server.py
   ```

### 7. Set Up the Service

1. Create the service file:
   ```bash
   sudo nano /etc/systemd/system/ais_server.service
   ```
2. Add the following content (modify paths if needed):
   ```
   [Unit]
   Description=AIS Server Service
   After=network.target

   [Service]
   User=JLBMaritime
   ExecStart=/bin/bash -c 'source /home/JLBMaritime/ais_project/ais_env/bin/activate && python3 /home/JLBMaritime/ais_project/ais_server.py'
   Restart=always
   RestartSec=5

   [Install]
   WantedBy=multi-user.target
   ```
3. Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable ais_server.service
   sudo systemctl start ais_server.service
   ```

## Network Configuration

### Basic Network Setup

The AIS data forwarding system requires network connectivity to transmit AIS data to the target device. The data flow is as follows:

1. AIS signals are received by the antenna
2. The dAISy HAT processes these signals and sends them to the Raspberry Pi via serial
3. The Python script reads the data from the serial port
4. The script forwards the data to the configured IP address and port over TCP/IP

### WiFi Configuration

To configure WiFi on your Raspberry Pi:

1. List available WiFi networks:
   ```bash
   sudo nmcli dev wifi list
   ```

2. Connect to a WiFi network:
   ```bash
   nmcli connection add type wifi ifname wlan0 con-name "MySSID" ssid "MySSID"
   nmcli connection modify "MySSID" wifi-sec.key-mgmt wpa-psk
   nmcli connection modify "MySSID" wifi-sec.psk "your_password"
   nmcli connection modify "MySSID" connection.autoconnect yes
   ```

3. Verify the connection:
   ```bash
   nmcli connection show "MySSID"
   ```

4. View connection details including passwords:
   ```bash
   nmcli connection show "MySSID" --show-secrets
   ```

5. Check current connections:
   ```bash
   sudo nmcli dev wifi list
   ```

### Ethernet Configuration

For a more reliable connection, consider using Ethernet:

1. To set a static IP address for the Ethernet interface:
   ```bash
   sudo nano /etc/dhcpcd.conf
   ```

2. Add the following lines (modify as needed):
   ```
   interface eth0
   static ip_address=192.168.1.10/24
   static routers=192.168.1.1
   static domain_name_servers=192.168.1.1 8.8.8.8
   ```

3. Restart the networking service:
   ```bash
   sudo systemctl restart dhcpcd
   ```

### Target Device Configuration

The target device (at the configured IP and port) should be set up to receive TCP data. This could be:

- A chart plotter with network capabilities
- A computer running navigation software
- Another Raspberry Pi running a data processing application

Ensure the target device is:
1. Powered on and connected to the same network
2. Configured to listen on the specified port
3. Able to process NMEA AIS sentences

## Testing and Verification

### Testing the Serial Connection

To verify the dAISy HAT is working correctly:

```bash
screen /dev/serial0 38400
```

If properly configured, pressing ESC will bring up the configuration menu. Press ESC again to return to receive mode. Exit screen by pressing CTRL-A, release, then press K (kill) and Y to confirm.

### Checking the Service Status

To verify the service is running:

```bash
sudo systemctl status ais_server.service
```

### Monitoring the Logs

To view the service logs in real-time:

```bash
journalctl -u ais_server.service -f
```

## Troubleshooting

### Serial Port Issues

1. Verify the serial port is enabled in raspi-config
2. Check if the dAISy HAT is properly seated on the GPIO pins
3. Try a different serial port (e.g., `/dev/ttyAMA0` instead of `/dev/serial0`)

### Network Issues

1. Verify network connectivity:
   ```bash
   ping 192.168.1.100
   ```
2. Check if the target port is open:
   ```bash
   nc -zv 192.168.1.100 12345
   ```
3. Verify the service is running and not encountering errors

### Service Issues

1. Check service status:
   ```bash
   sudo systemctl status ais_server.service
   ```
2. View detailed logs:
   ```bash
   journalctl -u ais_server.service
   ```
3. Verify the paths in the service file match your actual installation

## Advanced Configuration

### Changing the Target IP and Port

Edit the configuration file:

```bash
nano ~/ais_project/ais_config.conf
```

Update the `ip` and `port` values, then restart the service:

```bash
sudo systemctl restart ais_server.service
```

### Adjusting Retry Parameters

The script attempts to reconnect to the target device up to 3 times by default. To modify this behavior, edit the `send_data` function in `ais_server.py`.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Thanks to the dAISy HAT project for providing affordable AIS reception capabilities
- The Raspberry Pi Foundation for their excellent single-board computers
