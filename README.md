**avahi-hosts**  
   
Automatically Generate hosts records from the LAN's Avahi Browser data.
This solution is intended to integrate with Pi-hole for automating DNS resolution on your LAN, especially when you cannot rely on Pi-hole's integrated DHCP service. Pi-hole doesn't support Dynamic DNS Updates (RFC 2136), and this script bridges that gap by updating the `custom.list` file with local hostnames.  
<img src="https://github.com/ElSrJuez/avahi-hosts/blob/main/res/avahi-hosts-logo.png" alt="avahi-hosts-logo" width="25%">

---  
   
**Table of Contents**  
   
1. About  
2. Features  
3. Prerequisites  
4. Installation  
5. Usage  
6. Configuration  
7. Automating Execution  
8. Examples  
9. Contributing  
10. License  
11. Acknowledgments  
   
---  
   
### 1. About  
   
The **avahi-hosts** project provides a solution for generating a static hosts file using Avahi's mDNS/Bonjour service discovery. It is primarily intended for use with Pi-hole to maintain accurate DNS records of devices on your local network when Pi-hole's integrated DHCP service isn't suitable.  
   
Pi-hole lacks support for Dynamic DNS Updates (RFC 2136), which can make hostname resolution challenging in dynamic network environments. This script leverages Avahi to detect active hosts and updates Pi-hole's `custom.list` file, ensuring that hostnames are correctly resolved on your LAN.  
   
---  
   
### 2. Features  
   
- **Automated Host Discovery**: Uses `avahi-browse` to discover devices on the local network.  
- **Static Hosts File Generation**: Creates or updates a hosts file compatible with Pi-hole.  
- **Customizable Purge Time**: Configurable duration to remove inactive hosts from the database.  
- **Flexible Hostname Suffix**: Allows setting a custom domain suffix for hostnames.  
- **Debug Mode**: Provides detailed logs for troubleshooting.  
- **Persistency**: Maintains a database of known hosts with timestamps.  
   
---  
   
### 3. Prerequisites  
   
- **Operating System**: Linux (tested on Ubuntu 24.04)  
- **Dependencies**:  
  - `avahi-utils`: Provides the `avahi-browse` command.  
  - `bash`: The script uses Bash shell features.  
- **Permissions**: The script must be run with root privileges since it updates system files.  
   
---  
   
### 4. Installation  
   
1. **Clone the Repository**  
  
   ```bash  
   git clone https://github.com/your_username/avahi-hosts.git  
   cd avahi-hosts  
   ```  
   
2. **Copy the Script**  
  
   Place the `avahi-hosts.sh` script into a directory in your `PATH`, such as `/usr/local/bin/`:  
  
   ```bash  
   sudo cp avahi-hosts.sh /usr/local/sbin/  
   sudo chmod +x /usr/local/sbin/avahi-hosts.sh  
   ```  
   
3. **Install Dependencies**  
  
   Ensure `avahi-utils` is installed on your system:  
  
   ```bash  
   sudo apt update  
   sudo apt install avahi-utils  
   ```  
   
4. **Create Data Directory**  
  
   The script uses `/etc/avahi-hosts/data` to store its database file. It also creates this directory automatically, but if not:  
  
   ```bash  
   sudo mkdir -p /etc/avahi-hosts 
   ```  
  
   Ensure it has the correct permissions:  
  
   ```bash  
   sudo chmod 755 /etc/avahi-hosts  
   ```  
   
---  
   
### 5. Usage  
   
Run the script with elevated privileges:  
   
```bash  
sudo avahi-hosts.sh -f /path/to/pihole/custom.list  
```  
   
**Options**  
   
- `-f output_hosts_file`: Specify the output hosts file path (default: `/path/to/pihole/custom.list`).  
- `-s hostname_suffix`: Specify the hostname suffix for the local network (default: `.lan`).  
- `-d`: Enable debug mode for detailed output.  
- `-h`: Display help message.  
   
**Example**  
   
```bash  
sudo avahi-hosts.sh -d -f /etc/pihole/custom.list -s .local  
```  
   
This command runs the script in debug mode, outputs the hosts to `/etc/pihole/custom.list`, and uses `.local` as the hostname suffix.  
   
---  
   
### 6. Configuration  
   
#### Purge Time  
   
The default purge time is **2880 minutes** (2 days). To change this, edit the `avahi_hosts.db` file located in `/etc/avahi-hosts/data/` and modify the line starting with `# x=` to your desired purge time in minutes.  
   
```bash  
sudo nano /var/lib/avahi-hosts/avahi_hosts.db  
```  
   
Change:  
   
```plaintext  
# x=2880  
```  
   
To:  
   
```plaintext  
# x=desired_purge_time_in_minutes  
```  
   
#### Hostname Suffix  
   
If your network uses a different domain suffix, use the `-s` option to specify it when running the script.  
   
---  
   
### 7. Automating Execution  
   
To run the script automatically every 12 hours, you can use either **systemd timers**. Here, we'll explain how to use systemd timers.  
   
#### Using systemd Timers  
   
1. **Create systemd Service and Timer Files**  
  
   ```bash  
   sudo cp systemd/avahi-hosts.* /etc/systemd/system/
   sudo nano /etc/systemd/system/avahi-hosts.service  
   ```  
  
   **Content:**  
  
   ```  
   [Unit]  
   Description=Avahi Hosts Script for PiHole   
  
   [Service]  
   Type=oneshot  
   ExecStart=/usr/local/bin/avahi-hosts.sh -f /etc/pihole/custom.list  
   ```  
   
2. **Create a systemd Timer File**  
  
   ```bash  
   sudo nano /etc/systemd/system/avahi-hosts.timer  
   ```  
  
   **Content:**  
  
   ```  
   [Unit]  
   Description=Run Avahi Hosts Update every 12 hours  
  
   [Timer]  
   OnBootSec=15min  
   OnUnitActiveSec=12h  
   Persistent=true  
  
   [Install]  
   WantedBy=timers.target  
   ```  
   
3. **Reload systemd and Enable the Timer**  
  
   ```bash  
   sudo systemctl daemon-reload  
   sudo systemctl enable avahi-hosts.timer  
   sudo systemctl start avahi-hosts.timer  
   ```  
   
4. **Verify the Timer**  
  
   ```bash  
   systemctl list-timers avahi-hosts.timer  
   ```  
  
   This command will show when the timer last ran and when it is scheduled to run next.  
   
#### Viewing Debug Output  
   
To troubleshoot, run the script in debug mode:  
   
```bash  
sudo avahi-hosts.sh -d -f /etc/pihole/custom.list  
```  
   
This will output detailed information about the discovery process, host selection, and any issues encountered.  
   
---  
   
### 9. Contributing  
   
Contributions are welcome! 
For significant changes, please open an issue first to discuss what you'd like to change.  
   
**Coding Standards**  
   
- **ShellCheck**: Please ensure your Bash code passes ShellCheck linting.  
- **Comments**: Include comments explaining complex sections of code.  
- **Style**: Follow consistent indentation and coding style throughout the script.  
   
---  
   
### 10. License  
   
This project is licensed under the **MIT License**. See the `LICENSE` file for details.  
   
---  
   
### 11. Acknowledgments  
   
- **Pi-hole**: A network-wide ad blocker that this project integrates with.  
- **Avahi**: A system which facilitates service discovery on a local network.  
- **Community Contributors**: Thank you to everyone who has contributed to this project.  
   
---  
   
If there's anything you'd like me to add or adjust in this README document, please let me know!
