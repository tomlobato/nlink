#!/bin/bash

enable_conmark=true

function usage	{
	echo "uso: $0 [flush] [table=<table>] [prio=<prio>]"
	exit 1
}

[ $# -gt 3 ] && usage

flush=false
[ "$1" == flush ] && {
	flush=true
	shift
}

for arg in $*; do
	echo $arg | egrep -q '=' || usage
	var=`echo $arg| sed s/=.*//`
	[[ "$var" != prio && "$var" != table ]] && usage
	export $arg
done

[ -n "$prio" ] && ! `echo $prio | egrep -q '^[0-9]+$'` && usage

if [ -z "$table" ]; then
	seltable=faster
else
	seltable=$table
fi

[ -z "$prio" ] &&  prio=70

list1="
a.b.c.d/24
1.2.3.4/28"

list2="
a.b.c.d/24
1.2.3.4/28"

ips=`echo $list1 $list2 97.107.136.121`

function down
{
	functable=$1
	
	ip ru del prio $prio fwmark 0x25110 lookup $functable 2> /dev/null
	for ip in $ips; do
		ip ru del prio $prio to $ip table $functable 2> /dev/null
	done
}
	
$enable_conmark&&{
	ip ru del prio $prio fwmark 0x1 table 21 2> /dev/null
	ip ru del prio $prio fwmark 0x2 table 22 2> /dev/null
	#ip ru del prio $prio fwmark 0x3 table 23 2> /dev/null
}
	
if [[ -n "$table" && "$flush" == true ]]; then
	down $table
else
	for i in `seq 1 3`; do
		down $(( 20 + $i ))
	done
fi
	
$flush && exit
	
ip ru add prio $prio fwmark 0x25110 lookup $seltable

$enable_conmark&&{
	ip ru add prio $prio fwmark 0x1 table 21
	ip ru add prio $prio fwmark 0x2 table 22
	#ip ru add prio $prio fwmark 0x3 table 23
}

for ip in $ips; do
	ip ru add prio $prio to $ip table $seltable
done

