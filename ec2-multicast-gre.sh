#!/bin/bash
#
# Based on the MCD concept described at https://aws.amazon.com/articles/6234671078671125
#
# Allows EC2 instances to send multicast messages to each other via a GRE tunnel mesh.
# The script automatically creates the mesh by querying EC2 for all instances in the
# region that have a 'multicast' tag with the same value as the instance the script is
# run from.
#
# To use the script, ensure that instances have an ec2 tag with key name 'multicast' and
# that all instances in the intended multicast group have the same value for the tag.
# Then, each instance should run the script at startup (i..e via user-data) and also
# should run the script periodically via a cron job.
# 

METADATA=http://169.254.169.254/latest/meta-data
BRIDGE=${MULTICAST_BRIDGE-mcgrebr}
EC2TAG=${MULTICAST_TAG-multicast}

# Install packages
which aws &>/dev/null || easy_install awscli
which brctl &>/dev/null || yum install -y bridge-utils
which ebtables &>/dev/null || yum install -y ebtables

# get info from EC2
# get id and region from meta-data api
id=`curl -sS $METADATA/instance-id`
export AWS_DEFAULT_REGION=`curl -sS \
    $METADATA/placement/availability-zone/ | head -c -1`
# get value of 'multicast' EC2 tag for this instance
multicast=`aws ec2 describe-tags \
    --filters "Name=resource-id,Values=$id" "Name=key,Values=$EC2TAG" \
    --output=text | cut -f5`
# get list of ips for other instances that have the same tag value
ips=`aws ec2 describe-instances \
    --filters "Name=tag:$EC2TAG,Values='$multicast'" \
    --query "Reservations[].Instances[?InstanceId!='$id'].[PrivateIpAddress]" \
    --output text`

# Exit if we don't have a list of ip addresses
if [[ ! "$ips" ]]; then
    [[ ! "$multicast" ]] && echo "Tag '$EC2TAG' not found on instance!" ||
        echo "No other instances found with '$EC2TAG' tag value '$multicast'!"
    exit 1
fi

myip=`ip -o -4 addr show eth0 | awk '{gsub(/\/.*/, ""); print $4}'`

# Set up bridge if it doesn't exist already
brctl show | grep -q "^$BRIDGE\s" >/dev/null || {
    brctl addbr $BRIDGE
    ip link set $BRIDGE up
    # assume that 10.255.0.0/16 doesn't need to be routed anywhere
    a=(${myip//./ })
    ip addr add 10.255.${a[2]}.${a[3]}/16 dev $BRIDGE
    ip route add 224.0.0.0/4 dev $BRIDGE
}

# Set up GRE tunnel mesh
taplist=""
for ip in $ips; do
    tap=gretap-`printf '%02X' ${ip//./ }`
    taplist="$taplist $tap"
    test -e /sys/class/net/$tap || {
        ip link add $tap type gretap local $myip remote $ip
        ip link set dev $tap up
        ebtables -A FORWARD -i gretap-+ -o gretap-+ -j DROP
        brctl addif $BRIDGE $tap
    }
done

# Remove tunnels to instances no longer in list returned by querying for multicast tag
for tap in `ls /sys/class/net/$BRIDGE/brif/`; do
  [[ ! "$taplist" =~ "$tap" ]] && ip link del $tap
done
