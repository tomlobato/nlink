######################################################
# NAT
######################################################
iptables -t nat -F

##################
# NET SHARE / SNAT
echo 1 > /proc/sys/net/ipv4/ip_forward
#iptables -t nat -o $if_wan -A POSTROUTING -s $ip_lan_net -j SNAT --to $ip_wan

/usr/local/sbin/nlinks iptables_mangle_forward
/usr/local/sbin/nlinks iptables_nat_postrouting

