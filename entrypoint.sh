#!/bin/bash
# Light jail setup
# By dominic@sensepost.com
# All rights reserved. 2018

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

export DEBIAN_FRONTEND=noninteractive
# Do these in the Dockerfile, but leave it here in case you're using another system
#apt-get update -o Dir::Etc::sourcelist="sources.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
#apt-get install -y resolvconf iproute2 psmisc iptables iputils-ping

# Create user name space resolv.conf
mkdir /etc/interfaces
touch /etc/enable-updates
mkdir /etc/netns
mkdir /etc/netns/USER
mkdir /etc/netns/USER/interfaces
touch /etc/netns/USER/enable-updates
echo "nameserver 8.8.8.8" > /etc/netns/USER/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolvconf/resolv.conf.d/tail
# Create the user namespace
ip netns add USER 
# Hide adapters in it's own network namespace

# Set up the user's light jail. We want to hide /opt, /mnt & /tmp. /proc needs
# somE special handling so we can use unshare's --mount-proc. /sys also needs
# different handling.
chroot_dir="/mnt/user"
mkdir $chroot_dir
for x in $(ls -d /*/); do
  if [ $x == "/opt/" ]; then
    continue
  elif [ $x == "/mnt/" ]; then
    continue
  elif [ $x == "/sys/" ]; then
    mkdir $chroot_dir/sys
    continue
  elif [ $x == "/proc/" ]; then
    mkdir $chroot_dir/proc
    mount --bind $chroot_dir/proc $chroot_dir/proc
    continue
  elif [ $x == "/tmp/" ]; then
    mkdir $chroot_dir/tmp
    continue
  fi
  mkdir $chroot_dir$x
  mount --bind $x $chroot_dir$x
done

# Safety rails to prevent user killing their primary shell with exit or Ctrl-D
echo "if [ \$\$ -eq 1 ]; then alias exit='echo Primary shell refusing to exit'; export IGNOREEOF=10; fi" >> ~/.bashrc

# Change the shell to our light jail
echo /bin/nssh >> /etc/shells \
  && chsh -s /bin/nssh

# Define user network name space variables
upstream=$(ip route list 0.0.0.0/0|awk '{print $5}')
user_ns="USER"
user_ip="10.0.0"
user_veth=eth1
user_chroot="/mnt/user/"
user_pid=$(pgrep unshare|head -n1)
if [ ! $(( $user_pid +1 )) -eq 1 ]; then
  user_bashpid=$(pstree -p $user_pid|sed "s/^.*bash(\([0-9]*\)).*$/\1/"|head -n1)
else
  user_pid=0
  user_bashpid=0
fi

# Check if we have internet in the USER namespace
ip netns exec $user_ns ping -c1 -w1 8.8.8.8 2> /dev/null
# If we don't set it up
if [[ ! $? -eq 0 ]]; then
  # Create a veth pair & give them IPs
  ip link add $user_veth type veth peer name $user_veth netns $user_ns
  ip addr add $user_ip.1/24 dev $user_veth
  ip link set up dev $user_veth
  ip -n $user_ns addr add $user_ip.2/24 dev $user_veth
  ip -n $user_ns link set up dev $user_veth
  # Make the root namespace our gateway
  ip -n $user_ns route add default via $user_ip.1 dev $user_veth
  # Set up NAT between them
  echo '1' > /proc/sys/net/ipv4/ip_forward
  # Check if we have the rules already to prevent duplicates
  iptables -t nat -C POSTROUTING -o $upstream -j MASQUERADE 2> /dev/null
  if [[ ! $? -eq 0 ]]; then
    iptables -t nat -A POSTROUTING -o $upstream -j MASQUERADE
    iptables -A FORWARD -i $user_veth -o $upstream -j ACCEPT
    iptables -A FORWARD -i $upstream -o $user_veth -j ACCEPT
  fi
fi

# Check if our user chroot is up
if [ ! $user_bashpid -eq 0 ]; then
  # Check if resolvconf is mounted
  nsenter -t $user_bashpid --pid --net --mount chroot $user_chroot mount|grep "/run/resolvconf"
  if [ $? -eq 1 ]; then
    # Mount it
    nsenter -t $user_bashpid --pid --net --mount chroot $user_chroot mount -o bind /etc/netns/$user_ns /run/resolvconf
  fi
fi

