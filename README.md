Nlink allows your linux server to connect to multiple ISP\`s, mainly featuring load balancing and failover.

Built on top of Linux, Iproute, Iptables.

## Features

- Failover based on ICMP (ping to external hosts). Multiple externals hosts can be set for each link. 
- Load balancing: multiple links can be used at same time and the bandwidth usage distributed among them. 
- Open source. 
- Beside ICMP for failover, the bandwidth on the link is checked to avoid false negatives.
