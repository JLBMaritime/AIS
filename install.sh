#!/bin/bash

# AIS Data Forwarding System Installation Script
# For Raspberry Pi with dAISy HAT

# Text formatting
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo -e "\n${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}$(printf '=%.0s' {1..50})${NC}\n"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (with sudo)"
        exit 1
    fi
}

# Function to check and set hostname
check_hostname() {
    current_hostname=$(hostname)
    if [ "$current_hostname" != "AIS" ]; then
        print_warning "Current hostname is '$current_hostname', not 'AIS'"
        read -p "Would you like to change the hostname to 'AIS'? (y/n): " change_hostname
        if [[ $change_hostname =~ ^[Yy]$ ]]; then
            echo "AIS" > /etc/hostname
            sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\tAIS/g" /etc/hosts
            print_success "Hostname will be changed to 'AIS' after reboot"
        else
            print_warning "Continuing with hostname '$current_hostname'"
        fi
    else
        print_success "Hostname is correctly set to 'AIS'"
    fi
}

# Function to check username
check_username() {
    current_user=$(whoami)
    if [ "$current_user" != "root" ]; then
        print_error "This script must be run with sudo"
        exit 1
    fi
    
    if id "JLBMaritime" &>/dev/null; then
        print_success "User 'JLBMaritime' exists"
        target_user="JLBMaritime"
    else
        print_warning "User 'JLBMaritime' does not exist"
        read -p "Would you like to create user 'JLBMaritime'? (y/n): " create_user
        if [[ $create_user =~ ^[Yy]$ ]]; then
            adduser --gecos "" JLBMaritime
            usermod -aG sudo JLBMaritime
            print_success "User 'JLBMaritime' created"
            target_user="JLBMaritime"
        else
            print_warning "Using current user for installation"
            read -p "Enter username to use for the service: " target_user
        fi
    fi
    
    # Export for use in other functions
    export TARGET_USER=$target_user
}

# Function to update the system
update_system() {
    print_section "Updating System Packages"
    
    apt update
    if [ $? -eq 0 ]; then
        print_success "Repository information updated"
    else
        print_error "Failed to update repository information"
        exit 1
    fi
    
    apt full-upgrade -y
    if [ $? -eq 0 ]; then
        print_success "System packages updated"
    else
        print_warning "Some issues occurred during system update"
    fi
}

# Function to install required packages
install_packages() {
    print_section "Installing Required Packages"
    
    apt install -y python3 python3-pip python3-venv screen
    if [ $? -eq 0 ]; then
        print_success "Required packages installed"
    else
        print_error "Failed to install required packages"
        exit 1
    fi
}

# Function to configure serial port
configure_serial() {
    print_section "Configuring Serial Port"
    
    # Disable serial console
    if grep -q "console=serial0" /boot/cmdline.txt; then
        sed -i 's/console=serial0,[0-9]\+ //' /boot/cmdline.txt
        print_success "Serial console disabled in cmdline.txt"
    else
        print_success "Serial console already disabled"
    fi
    
    # Enable serial hardware
    if grep -q "^enable_uart=1" /boot/config.txt; then
        print_success "UART already enabled in config.txt"
    else
        echo "enable_uart=1" >> /boot/config.txt
        print_success "UART enabled in config.txt"
    fi
    
    print_warning "A reboot will be required for serial port changes to take effect"
}

# Function to set up project directory and files
setup_project() {
    print_section "Setting Up Project Directory"
    
    # Create project directory
    project_dir="/home/$TARGET_USER/ais_project"
    mkdir -p $project_dir
    
    # Copy files from current directory to project directory
    if [ -f "src/ais_server.py" ]; then
        cp src/ais_server.py $project_dir/
        print_success "Copied ais_server.py to project directory"
    else
        # Create from the current script
        cat > $project_dir/ais_server.py << 'EOF'
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
    config_file = sys.argv[1] if len(sys.argv) > 1 else f"/home/{os.getenv('USER', 'JLBMaritime')}/ais_project/ais_config.conf"
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
    import os
    main()
EOF
        print_success "Created ais_server.py in project directory"
    fi
    
    # Make the script executable
    chmod +x $project_dir/ais_server.py
    
    # Create config file
    cat > $project_dir/ais_config.conf << EOF
[AIS]
serial_port = /dev/serial0
# Replace with your actual serial port
ip = 192.168.1.100
# Replace with the target IP address
port = 12345
# Replace with the target port number
EOF
    print_success "Created ais_config.conf in project directory"
    
    # Set ownership
    chown -R $TARGET_USER:$TARGET_USER $project_dir
    print_success "Set correct ownership for project directory"
}

# Function to set up Python virtual environment
setup_venv() {
    print_section "Setting Up Python Virtual Environment"
    
    project_dir="/home/$TARGET_USER/ais_project"
    
    # Create virtual environment
    su - $TARGET_USER -c "cd $project_dir && python3 -m venv ais_env"
    if [ $? -eq 0 ]; then
        print_success "Created Python virtual environment"
    else
        print_error "Failed to create Python virtual environment"
        exit 1
    fi
    
    # Install required packages
    su - $TARGET_USER -c "cd $project_dir && source ais_env/bin/activate && pip install pyserial && deactivate"
    if [ $? -eq 0 ]; then
        print_success "Installed required Python packages"
    else
        print_error "Failed to install required Python packages"
        exit 1
    fi
}

# Function to set up systemd service
setup_service() {
    print_section "Setting Up Systemd Service"
    
    # Create service file
    cat > /etc/systemd/system/ais_server.service << EOF
[Unit]
Description=AIS Server Service
After=network.target

[Service]
User=$TARGET_USER
ExecStart=/bin/bash -c 'source /home/$TARGET_USER/ais_project/ais_env/bin/activate && python3 /home/$TARGET_USER/ais_project/ais_server.py'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    print_success "Created systemd service file"
    
    # Reload systemd
    systemctl daemon-reload
    if [ $? -eq 0 ]; then
        print_success "Reloaded systemd configuration"
    else
        print_error "Failed to reload systemd configuration"
        exit 1
    fi
    
    # Enable service
    systemctl enable ais_server.service
    if [ $? -eq 0 ]; then
        print_success "Enabled ais_server service to start at boot"
    else
        print_error "Failed to enable ais_server service"
        exit 1
    fi
}

# Function to configure network
configure_network() {
    print_section "Network Configuration"
    
    read -p "Would you like to configure WiFi? (y/n): " configure_wifi
    if [[ $configure_wifi =~ ^[Yy]$ ]]; then
        # Check if NetworkManager is installed
        if ! command -v nmcli &> /dev/null; then
            print_warning "NetworkManager not found, installing..."
            apt install -y network-manager
        fi
        
        # List available networks
        echo "Available WiFi networks:"
        nmcli dev wifi list
        
        # Get network details
        read -p "Enter WiFi SSID: " wifi_ssid
        read -p "Enter WiFi password: " -s wifi_password
        echo ""
        
        # Configure WiFi
        nmcli connection add type wifi ifname wlan0 con-name "$wifi_ssid" ssid "$wifi_ssid"
        nmcli connection modify "$wifi_ssid" wifi-sec.key-mgmt wpa-psk
        nmcli connection modify "$wifi_ssid" wifi-sec.psk "$wifi_password"
        nmcli connection modify "$wifi_ssid" connection.autoconnect yes
        
        # Connect to WiFi
        nmcli connection up "$wifi_ssid"
        
        if [ $? -eq 0 ]; then
            print_success "Connected to WiFi network '$wifi_ssid'"
        else
            print_error "Failed to connect to WiFi network"
        fi
    else
        print_warning "Skipping WiFi configuration"
    fi
    
    read -p "Would you like to configure a static IP for Ethernet? (y/n): " configure_ethernet
    if [[ $configure_ethernet =~ ^[Yy]$ ]]; then
        read -p "Enter static IP address (e.g., 192.168.1.10/24): " static_ip
        read -p "Enter gateway IP (e.g., 192.168.1.1): " gateway_ip
        read -p "Enter DNS servers (space-separated, e.g., 192.168.1.1 8.8.8.8): " dns_servers
        
        # Configure static IP
        cat >> /etc/dhcpcd.conf << EOF

# Static IP configuration added by AIS installer
interface eth0
static ip_address=$static_ip
static routers=$gateway_ip
static domain_name_servers=$dns_servers
EOF
        
        # Restart networking
        systemctl restart dhcpcd
        
        print_success "Configured static IP for Ethernet"
    else
        print_warning "Skipping Ethernet static IP configuration"
    fi
}

# Function to test the setup
test_setup() {
    print_section "Testing Setup"
    
    # Check if serial port exists
    if [ -e "/dev/serial0" ]; then
        print_success "Serial port /dev/serial0 exists"
    else
        print_warning "Serial port /dev/serial0 does not exist"
        print_warning "You may need to reboot for serial port changes to take effect"
    fi
    
    # Check network connectivity to target
    target_ip=$(grep "ip =" /home/$TARGET_USER/ais_project/ais_config.conf | awk '{print $3}')
    ping -c 1 $target_ip > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "Target device at $target_ip is reachable"
    else
        print_warning "Target device at $target_ip is not reachable"
        print_warning "Make sure the target device is on the network and has the correct IP"
    fi
    
    # Start the service
    systemctl start ais_server.service
    sleep 2
    systemctl status ais_server.service > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_success "AIS server service started successfully"
    else
        print_warning "AIS server service failed to start"
        print_warning "Check logs with: journalctl -u ais_server.service"
    fi
}

# Function to display completion message
completion_message() {
    print_section "Installation Complete"
    
    echo -e "${BOLD}The AIS Data Forwarding System has been installed!${NC}"
    echo ""
    echo "Configuration file: /home/$TARGET_USER/ais_project/ais_config.conf"
    echo "Server script: /home/$TARGET_USER/ais_project/ais_server.py"
    echo "Service file: /etc/systemd/system/ais_server.service"
    echo ""
    echo "Useful commands:"
    echo "  - Check service status: sudo systemctl status ais_server.service"
    echo "  - View logs: journalctl -u ais_server.service -f"
    echo "  - Test serial port: screen /dev/serial0 38400"
    echo "  - Restart service: sudo systemctl restart ais_server.service"
    echo ""
    
    if [ "$(hostname)" != "AIS" ]; then
        print_warning "A reboot is recommended to apply hostname changes"
    fi
    
    if grep -q "enable_uart=1" /boot/config.txt && ! [ -e "/dev/serial0" ]; then
        print_warning "A reboot is required to enable the serial port"
    fi
    
    read -p "Would you like to reboot now? (y/n): " reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        echo "Rebooting in 5 seconds..."
        sleep 5
        reboot
    else
        echo "Remember to reboot later to apply all changes."
    fi
}

# Main installation process
main() {
    print_section "AIS Data Forwarding System Installation"
    
    check_root
    check_hostname
    check_username
    update_system
    install_packages
    configure_serial
    setup_project
    setup_venv
    setup_service
    configure_network
    test_setup
    completion_message
}

# Run the main installation process
main
