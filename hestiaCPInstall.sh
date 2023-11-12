#!/bin/bash

#   ___ ___                   __  .__       ___________________  .___                 __         .__  .__      _________            .__        __    #
#  /   |   \   ____   _______/  |_|__|____  \_   ___ \______   \ |   | ____   _______/  |______  |  | |  |    /   _____/ ___________|__|______/  |_  #
# /    ~    \_/ __ \ /  ___/\   __\  \__  \ /    \  \/|     ___/ |   |/    \ /  ___/\   __\__  \ |  | |  |    \_____  \_/ ___\_  __ \  \____ \   __\ #
# \    Y    /\  ___/ \___ \  |  | |  |/ __ \\     \___|    |     |   |   |  \\___ \  |  |  / __ \|  |_|  |__  /        \  \___|  | \/  |  |_> >  |   #
#  \___|_  /  \___  >____  > |__| |__(____  /\______  /____|     |___|___|  /____  > |__| (____  /____/____/ /_______  /\___  >__|  |__|   __/|__|   #
#        \/       \/     \/               \/        \/                    \/     \/            \/                    \/     \/         |__|          #
#   by Ramo Molise                                                                                                                                   #

# Prompting user details

echo "Enter Hostname URL: "
read hostname

echo -e "\nWhich Port would you like to access Hestia CP: "
read port

echo -e "\nEnter Email Address: "
read email

echo -e "\nEnter admin Password: "
read password

# Confirm Details
echo "Are your details correct?"

echo -e "\n\nHostname: $hostname"
echo "Port: $port"
echo "Email: $email"
echo -e "Password: $password\n\n"

read -p "Press any key to continue, or Ctrl-C to quit"

# Fetch and Install Hestia CP

wget https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh

bash hst-install.sh --port "$port" --interactive no --email $email --password "$password" --hostname $hostname -f

