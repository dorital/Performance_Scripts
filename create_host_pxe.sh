#!/bin/bash
for host in `cat /etc/dhcp/dhcpd.conf|grep host|awk  '{print $2}'`;do
   mac=`cat /etc/dhcp/dhcpd.conf|grep -w $host|awk  -F " |;" '{print $6}'|sed -e 's/:/-/g'`
   echo $host $mac
   cp /var/lib/tftpboot/pxelinux/pxelinux.cfg/01-esxi67 /var/lib/tftpboot/pxelinux/pxelinux.cfg/${host}-${mac}
done

exit

