#!/bin/bash  
  
# Default configuration  
DATA_FOLDER="/var/lib/avahi-hosts/"  
DB_FILE="$DATA_FOLDER/avahi_hosts.db"  # Database file to store host entries with timestamps  
OUTPUT_HOSTS_ABSOLUTE_PATH="/path/to/pihole/custom.list"  # Default output hosts file path
HOSTNAME_SUFFIX=".lan"  # Default hostname suffix for local network  
  
DEBUG=0  # Default debug mode disabled  
PURGE_TIME_DEFAULT=2880  # Default purge time in minutes (e.g., 2 days)  
  
# Function to display usage information
usage() {
    echo "Usage: $0 [-f output_hosts_file] [-s hostname_suffix] [-d] [-h]"
    echo "  -f output_hosts_file  Specify the output hosts file path."
    echo "  -s hostname_suffix    Specify the hostname suffix for local network."
    echo "  -d                    Enable debug mode."
    echo "  -h                    Display this help message."
    exit 1
}

# Parse command-line options  
while getopts ":f:s:dh" opt; do  
    case $opt in  
        f)  
            OUTPUT_HOSTS_ABSOLUTE_PATH="$OPTARG"  
            ;;  
        s)
            HOSTNAME_SUFFIX="$OPTARG"
            ;;
        d)  
            DEBUG=1  
            ;;  
        h)  
            usage  
            ;;  
        *)  
            usage  
            ;;  
    esac  
done  
shift $((OPTIND -1))
  
# Function to log debug messages  
debug_log() {  
    if [ "$DEBUG" -eq 1 ]; then  
        echo "$@"  
    fi  
}  
  
# Function to handle errors and exit  
die() {  
    echo "Error: $1" >&2  
    exit 1  
}  
  
# Check if running as root  
if [ "$EUID" -ne 0 ]; then  
    die "This script must be run with elevated privileges (as root). Please run using sudo or as root."  
fi  
  
# Create data folder if it doesn't exist  
if ! mkdir -p "$DATA_FOLDER"; then  
    die "Failed to create data directory '$DATA_FOLDER'. Check permissions."  
fi  
  
# Create the database file if it doesn't exist  
if [[ ! -f "$DB_FILE" ]]; then  
    echo "Database file '$DB_FILE' does not exist. Creating a new one."  
    {  
        echo "# This file contains custom host entries"  
        echo "# Format: IP hostname  # Last discovered: timestamp"  
        echo "# Purge time in minutes x=xx # Default: $PURGE_TIME_DEFAULT minutes"  
        echo "# x=$PURGE_TIME_DEFAULT"  
        echo "#"  
    } > "$DB_FILE" || die "Failed to write to database file '$DB_FILE'."  
    chmod 644 "$DB_FILE" || die "Failed to set permissions on '$DB_FILE'."  
fi  
  
echo "Reading purge time from the database file..."  
# Validate and read the purge time  
x=$(grep -E '^# x=[0-9]+$' "$DB_FILE" | sed 's/# x=//')  
  
if ! [[ "$x" =~ ^[0-9]+$ ]]; then  
    x="$PURGE_TIME_DEFAULT"  
    echo "Purge time not set or invalid in database file. Using default: $x minutes."  
else  
    echo "Purge time set to: $x minutes."  
fi  
  
current_time=$(date '+%s')  # Current epoch time  
  
echo "Discovering current hosts using avahi-browse..."  
  
# Declarations  
declare -A current_hosts_ips  
declare -A current_hosts_interfaces  
declare -A services_discovered  # Key: service category, Value: comma-separated hostnames  
declare -A host_services        # Key: hostname, Value: comma-separated service categories  
  
# Service categories mapping  
declare -A SERVICE_CATEGORIES=(  
    ["_workstation._tcp"]="Workstation"  
    ["_http._tcp"]="Web"  
    ["_https._tcp"]="Web"  
    ["_smb._tcp"]="File Sharing"  
    ["_afpovertcp._tcp"]="File Sharing"  
    ["_ssh._tcp"]="SSH"  
    ["_ftp._tcp"]="FTP"  
    ["_ipp._tcp"]="Printer"  
    ["_printer._tcp"]="Printer"  
    ["_ipps._tcp"]="Printer"  
    ["_scanner._tcp"]="Scanner"  
    ["_daap._tcp"]="Media"  
    ["_airplay._tcp"]="Media"  
    ["_raop._tcp"]="Media"  
    ["_ehttp._tcp"]="Web"  
    ["_airport._tcp"]="AirPort"  
    ["_wprint._tcp"]="Printer"  
    ["_ippusb._tcp"]="Printer"  
    ["_esphomelib._tcp"]="IoT"  
    ["_hap._tcp"]="HomeKit"  
    ["_dlna-ms._tcp"]="Media"  
    ["_device-info._tcp"]="Device Info"  
    ["_linux._tcp"]="Linux Device"  
    ["_udisks-ssh._tcp"]="File Sharing"  
    ["_pdl-datastream._tcp"]="Printer"  
    ["_privet._tcp"]="Printer"  
    ["_uscans._tcp"]="Scanner"  
    ["_uscan._tcp"]="Scanner"  
    ["_http-alt._tcp"]="Web"  
    ["_ipp-tls._tcp"]="Printer"  
    ["_googlecast._tcp"]="Media"  
    ["_companion-link._tcp"]="Media"  
    ["_spotify-connect._tcp"]="Media"  
    ["_homekit._tcp"]="Home Automation"  
    ["_nfs._tcp"]="File Sharing"  
    ["_sftp-ssh._tcp"]="File Sharing"  
    ["_telnet._tcp"]="Remote Access"  
    ["_remotewakeup._udp"]="Remote Wakeup"  
    ["_rdp._tcp"]="Remote Desktop"  
    ["_pulse-server._tcp"]="Media"  
    ["_nut._tcp"]="UPS"  
    ["_printer._sub._ipps._tcp"]="Printer"  
    ["_ipp._sub._ipp._tcp"]="Printer"  
    ["_ipps._sub._ipps._tcp"]="Printer"  
    # Additional service types from your output  
    ["Web Site"]="Web"  
    ["Device Info"]="Device Info"  
    ["Microsoft Windows Network"]="File Sharing"  
    ["Amazon Fire TV"]="Media"  
    ["Secure Internet Printer"]="Printer"  
    ["Internet Printer"]="Printer"  
    ["PDL Printer"]="Printer"  
    ["_occam._udp"]="IoT"  
    ["_apple-mobdev2._tcp"]="Mobile Device"  
    ["_meshcop._udp"]="IoT"  
    ["_matterd._udp"]="Matter Device"  
    ["_dosvc._tcp"]="Windows Update Service"  
    # Add more mappings as needed  
)  
  
# Temporarily disable die function
original_die=$(declare -f die)
die() { :; }

avahi_output=$(timeout 10s avahi-browse --parsable --all --resolve 2>/dev/null)
avahi_status=$?

# Restore die function
eval "$original_die"

if [ -z "$avahi_output" ]; then
    echo "avahi-browse command returned empty output."
    exit 1
fi

if [ $avahi_status -eq 124 ]; then
    echo "avahi-browse command timed out which is likely the expected status $avahi_status."
elif [ $avahi_status -ne 0 ]; then
    echo "avahi-browse command failed with status $avahi_status or timed out. Ensure avahi-utils is installed and running."
    exit 1
else
    echo "avahi-browse command completed successfully."
fi

while IFS=';' read -ra parts; do  
    if [[ "${parts[0]}" == "=" ]]; then  
        # Extract fields from avahi-browse output  
        interface="${parts[1]}"  
        protocol="${parts[2]}"  
        service_name="${parts[3]}"  
        service_type="${parts[4]}"  
        domain="${parts[5]}"  
        host_fullname="${parts[6]}"  
        ip_address="${parts[7]}"  
        port="${parts[8]}"  
        txt_records=("${parts[@]:9}")  
  
        # Map service_type to category  
        service_category="Other"  
        if [[ -n "${SERVICE_CATEGORIES[$service_type]}" ]]; then  
            service_category="${SERVICE_CATEGORIES[$service_type]}"  
        else  
            debug_log "Unknown service type: $service_type"  
        fi  
  
        # Extract and sanitize hostname  
        hostname="${host_fullname%.*}"  # Remove .local  
        declare -A txt_dict  
        for record in "${txt_records[@]}"; do  
            key="${record%%=*}"  
            value="${record#*=}"  
            txt_dict["$key"]="$value"  
        done  
        # Prioritize hostname from TXT records  
        for key in DN CN MN FN md ty rd sa; do  
            if [[ -n "${txt_dict[$key]}" ]]; then  
                hostname="${txt_dict[$key]}"  
                break  
            fi  
        done  
        # Clean the hostname  
        hostname="${hostname// /_}"  
        hostname="${hostname//[^a-zA-Z0-9_\-]/}"  
  
        # Collect services  
        # Note: hosts can have multiple services  
        if [[ ! "${host_services["$hostname"]}" =~ $service_category ]]; then  
            host_services["$hostname"]+="$service_category,"  
        fi  
        if [[ ! "${services_discovered["$service_category"]}" =~ $hostname ]]; then  
            services_discovered["$service_category"]+="$hostname,"  
        fi  
  
        # Collect hosts  
        if [[ "$ip_address" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then  
            current_hosts_ips["$hostname"]+="$ip_address,"  
            current_hosts_interfaces["$hostname"]+="$interface,"  
            debug_log "Discovered host: $hostname at IP $ip_address on interface $interface, service $service_category"  
        else  
            debug_log "Skipping non-IPv4 address for host $hostname: $ip_address"  
        fi  
    fi  
done <<< "$avahi_output"  
  
if [ ${#current_hosts_ips[@]} -eq 0 ]; then  
    echo "No hosts discovered."  
else  
    echo "Discovery complete. ${#current_hosts_ips[@]} hosts found."  
fi  
  
echo "Reading existing hosts from the database file..."  
  
# Read existing hosts and timestamps  
declare -A existing_hosts  
declare -A timestamps  
declare -a config_lines  
declare -a initial_comment_lines  
  
# Check if database file is readable  
if [[ ! -r "$DB_FILE" ]]; then  
    die "Cannot read database file '$DB_FILE'. Check permissions."  
fi  
  
# Variables to control parsing  
hosts_section_started=0  
  
while read -r line; do  
    if [[ $hosts_section_started -eq 0 ]]; then  
        if [[ "$line" =~ ^#\ x= ]]; then  
            config_lines+=("$line")  
        elif [[ "$line" =~ ^# ]]; then  
            initial_comment_lines+=("$line")  
        elif [[ "$line" =~ ^$ ]]; then  
            # Skip empty lines  
            continue  
        elif [[ "$line" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+([^\ ]+).*#\ Last\ discovered:\ ([0-9]+)$ ]]; then  
            # Host entries start here  
            hosts_section_started=1  
            ip="${BASH_REMATCH[1]}"  
            hostname="${BASH_REMATCH[2]}"  
            timestamp="${BASH_REMATCH[3]}"  
            existing_hosts["$hostname"]="$ip"  
            timestamps["$hostname"]="$timestamp"  
            debug_log "Existing host: $hostname at IP $ip, last discovered at $timestamp"  
        else  
            # Other lines before host entries  
            initial_comment_lines+=("$line")  
        fi  
    else  
        if [[ "$line" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+([^\ ]+).*#\ Last\ discovered:\ ([0-9]+)$ ]]; then  
            ip="${BASH_REMATCH[1]}"  
            hostname="${BASH_REMATCH[2]}"  
            timestamp="${BASH_REMATCH[3]}"  
            existing_hosts["$hostname"]="$ip"  
            timestamps["$hostname"]="$timestamp"  
            debug_log "Existing host: $hostname at IP $ip, last discovered at $timestamp"  
        else  
            # After hosts entries, we don't need to read further  
            break  
        fi  
    fi  
done < "$DB_FILE"  
  
echo "Processing hosts..."  
  
declare -a host_entries  
  
# Update existing hosts and handle purging  
for hostname in "${!existing_hosts[@]}"; do  
    ip="${existing_hosts[$hostname]}"  
    timestamp="${timestamps[$hostname]}"  
  
    if [[ -n "${current_hosts_ips[$hostname]}" ]]; then  
        debug_log "Updating host $hostname"  
  
        # Reset variables  
        unset ips_array interfaces_array ip_interface_map best_ip best_iface  
        declare -a ips_array=()  
        declare -a interfaces_array=()  
        declare -A ip_interface_map=()  
        best_ip=""  
        best_iface=""  
  
        # Select the best IP  
        IFS=',' read -ra ips_array <<< "${current_hosts_ips[$hostname]}"  
        IFS=',' read -ra interfaces_array <<< "${current_hosts_interfaces[$hostname]}"  
        ips_array=("${ips_array[@]// /}")  
        interfaces_array=("${interfaces_array[@]// /}")  
  
        for i in "${!ips_array[@]}"; do  
            ip_addr="${ips_array[$i]}"  
            iface="${interfaces_array[$i]}"  
            if [[ -n "$ip_addr" && -n "$iface" ]]; then  
                ip_interface_map["$ip_addr"]="$iface"  
            fi  
        done  
  
        # Decide the best IP  
        best_ip=""  
        best_iface=""  
        for ip_candidate in "${!ip_interface_map[@]}"; do  
            iface="${ip_interface_map[$ip_candidate]}"  
  
            if [[ "$iface" == "lo" || "$iface" == docker* || "$iface" == "br-"* ]]; then  
                continue  
            fi  
  
            if [[ "$ip_candidate" == "127."* || "$ip_candidate" == "172."* ]]; then  
                continue  
            fi  
  
            if [[ -z "$best_iface" ]]; then  
                best_ip="$ip_candidate"  
                best_iface="$iface"  
            elif [[ "$best_iface" != "eth0" && "$iface" == "eth0" ]]; then  
                best_ip="$ip_candidate"  
                best_iface="$iface"  
            fi  
        done  
  
        if [[ -z "$best_ip" ]]; then  
            debug_log "No preferred IP found for $hostname, selecting from available IPs."  
            best_ip="${ips_array[0]}"  
        fi  
  
        ip="$best_ip"  
        timestamp="$current_time"  
        unset "current_hosts_ips[$hostname]"  
        unset "current_hosts_interfaces[$hostname]"  
    else  
        # Host not currently available  
        age=$(( (current_time - timestamp) / 60 ))  
        if (( age > x )); then  
            echo "Removing host $hostname - not seen for $age minutes."  
            continue  
        else  
            debug_log "Keeping host $hostname - last seen $age minutes ago."  
        fi  
    fi  
    host_entries+=("$ip $hostname  # Last discovered: $timestamp")  
done  
  
# Add new hosts  
for hostname in "${!current_hosts_ips[@]}"; do  
    debug_log "Adding new host $hostname"  
  
    # Reset variables  
    unset ips_array interfaces_array ip_interface_map best_ip best_iface  
    declare -a ips_array=()  
    declare -a interfaces_array=()  
    declare -A ip_interface_map=()  
    best_ip=""  
    best_iface=""  
  
    IFS=',' read -ra ips_array <<< "${current_hosts_ips[$hostname]}"  
    IFS=',' read -ra interfaces_array <<< "${current_hosts_interfaces[$hostname]}"  
    ips_array=("${ips_array[@]// /}")  
    interfaces_array=("${interfaces_array[@]// /}")  
  
    for i in "${!ips_array[@]}"; do  
        ip_addr="${ips_array[$i]}"  
        iface="${interfaces_array[$i]}"  
        if [[ -n "$ip_addr" && -n "$iface" ]]; then  
            ip_interface_map["$ip_addr"]="$iface"  
        fi  
    done  
  
    # Decide the best IP  
    best_ip=""  
    best_iface=""  
    for ip_candidate in "${!ip_interface_map[@]}"; do  
        iface="${ip_interface_map[$ip_candidate]}"  
  
        if [[ "$iface" == "lo" || "$iface" == docker* || "$iface" == "br-"* ]]; then  
            continue  
        fi  
  
        if [[ "$ip_candidate" == "127."* || "$ip_candidate" == "172."* ]]; then  
            continue  
        fi  
  
        if [[ -z "$best_iface" ]]; then  
            best_ip="$ip_candidate"  
            best_iface="$iface"  
        elif [[ "$best_iface" != "eth0" && "$iface" == "eth0" ]]; then  
            best_ip="$ip_candidate"  
            best_iface="$iface"  
        fi  
    done  
  
    if [[ -z "$best_ip" ]]; then  
        debug_log "No preferred IP found for $hostname, selecting from available IPs."  
        best_ip="${ips_array[0]}"  
    fi  
  
    ip="$best_ip"  
    timestamp="$current_time"  
    host_entries+=("$ip $hostname  # Last discovered: $timestamp")  
done  
  
echo "Backing up the existing database file..."  
  
# Backup the existing database file  
if ! cp "$DB_FILE" "${DB_FILE}.bak"; then  
    die "Failed to backup database file '$DB_FILE'. Check permissions."  
fi  
  
echo "Rebuilding the database file..."  
  
# Rebuild the database file with host entries, initial comments, and new script info  
{  
    for line in "${config_lines[@]}"; do  
        echo "$line"  
    done  
    for line in "${initial_comment_lines[@]}"; do  
        echo "$line"  
    done  
    for entry in "${host_entries[@]}"; do  
        echo "$entry"  
    done  
  
    echo ""  
  
    echo "#"  
    echo "# Script run at: $(date)"  
    echo "# Ran by user: $(whoami)"  
    echo "# On host: $(hostname)"  
    echo "#"  
    echo "# Services discovered:"  
    # Output services per category  
    for category in "${!services_discovered[@]}"; do  
        IFS=',' read -ra hostnames_array <<< "${services_discovered[$category]%,}"  
        unique_hostnames=($(printf "%s\n" "${hostnames_array[@]}" | sort -u))  
        echo "# $category services:"  
        for host in "${unique_hostnames[@]}"; do  
            echo "#   - $host"  
        done  
    done  
} > "$DB_FILE.tmp" || die "Failed to write to temporary database file '$DB_FILE.tmp'."  
  
# Replace the database file  
if ! mv "$DB_FILE.tmp" "$DB_FILE"; then  
    die "Failed to update database file '$DB_FILE'. Check permissions."  
fi  
  
echo "Database file '$DB_FILE' has been updated."  
  
# Now, write the output hosts file with only 'IP hostname' entries  
echo "Writing hosts entries to '$OUTPUT_HOSTS_ABSOLUTE_PATH'..."  
  
{  
    for entry in "${host_entries[@]}"; do  
        # Extract IP and hostname from the entry  
        # Entry format: IP hostname  # Last discovered: timestamp  
        if [[ "$entry" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)[[:space:]]+([^\ ]+) ]]; then  
            ip="${BASH_REMATCH[1]}"  
            hostname="${BASH_REMATCH[2]}"  
            echo "$ip $hostname$HOSTNAME_SUFFIX"
        fi  
    done  
} > "$OUTPUT_HOSTS_ABSOLUTE_PATH" || die "Failed to write to output hosts file '$OUTPUT_HOSTS_ABSOLUTE_PATH'. Check permissions."  
  
echo "Hosts file '$OUTPUT_HOSTS_ABSOLUTE_PATH' has been updated."  
  
echo "Script completed successfully."  