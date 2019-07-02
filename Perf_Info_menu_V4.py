#!/usr/bin/python -tt

import getopt
import subprocess
import sys
import os

menu_actions = {}

def ssh_cmd(target,cmd):
	full_cmd = 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes root@%s %s' %(target,cmd)
	cmd_return = subprocess.Popen(full_cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
	return cmd_return
	
def hosts_info(list="all",sort="name"):
	#print sys.argv[1]
	if list == "all":
		fccon_output = ssh_cmd('stcon.xiv.ibm.com','/opt/FCCon/fcconnect.pl -dbop showhosts|grep "Free\|Used"')
	else:
		fccon_output = ssh_cmd('stcon.xiv.ibm.com','/opt/FCCon/fcconnect.pl -dbop showhosts |grep Free')
	fccon_output.wait()
	host_list=[]
	host_list_noping=[]
	host_list_nossh=[]
	host_list_ok={}
	# creating the required host list based on DB
	for line in fccon_output.stdout.readlines():
		#host_list.append(line.split(",")[0])
		host=line.split(",")[0]
		host_os = line.split(",")[1]
	#for host in host_list:
		# checking hosts availability
#		host=host+".eng.rtca"
		ping_cmd = 'ping -c1 %s' %(host)
		ping = subprocess.Popen(ping_cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
		if ping.wait() !=0:
			#print "failed to ping host: %s" %(host)
			host_list_noping.append(host)
		else:
			#checking ssh connectivity
			ssh = ssh_cmd(host,'date')
			if ssh.wait() !=0:
				host_list_nossh.append(host)
			else:
				if host_os == 'linux':
					# getting Linux os version
					#os_version = os.popen("ssh root@%s cat /etc/redhat-release | cut -f 7 -d " ") %(host)
					os_version = ssh_cmd(host,'cat /etc/redhat-release | cut -f 7 -d " "').stdout.readline(3)
					#getting Java version
					java_version="na"
					java_version = ssh_cmd(host,'java -version 2>&1 | awk "/version/{print $NF}"').stdout.readline().rstrip('\n')
					#if java_version =='':
					#	java_version = "na"					
					# getting FC HBA info
					total_active = 0
					fc_speed = "na"
					fc_port_list = ssh_cmd(host,'ls /sys/class/fc_host/').stdout.readlines()
					total_ports = len(fc_port_list)
					for port in fc_port_list:
						#check status
						port_status = ssh_cmd(host,'cat /sys/class/fc_host/%s/port_state' %(port.rstrip('\n')))
						if port_status.wait() !=0:
							print "failed to detect fc status for %s" %(host)
						else:
							if port_status.stdout.readline().rstrip('\n') == 'Online':
								total_active = total_active + 1
								#check speed
								port_speed = ssh_cmd(host,'cat /sys/class/fc_host/%s/speed' %(port.rstrip('\n')))
								if port_speed.wait()!=0:
									print "failed to detect fc speed for %s" %(host)
								else:
									fc_speed = port_speed.stdout.readline().rstrip('\n')
					if fc_speed.rsplit()[0].isdigit():
							host_bw = total_active*int(fc_speed.rsplit()[0])*100
					else:
						host_bw = 'na'
					iscsi_10Gb = ssh_cmd(host,'lspci |grep -i eth|grep "10-Gigabit\|10GbE"|wc -l').stdout.readline().rstrip('\n')
					total_cpu=ssh_cmd(host,'cat /proc/cpuinfo |grep processor|wc -l').stdout.readline().rstrip('\n')
					total_memory=ssh_cmd(host,'cat /proc/meminfo |grep MemTotal|awk "{print $2$3}"').stdout.readline().rstrip('\n')
					host_list_ok[host] = {'OS:':host_os,'version:':os_version,'java version:':java_version,'fc_speed:':fc_speed,'total_fc_ports:':total_ports,'total_fc_active:':total_active,'host_bw_MB/s:':host_bw,'total_cpu:':total_cpu,'total_memory:':total_memory,'iSCSI_10Gb:':iscsi_10Gb}
				elif host_os == 'esx':
					print "host %s is esxi" %(host)
					host_list_ok[host] = {'OS':host_os,'version':'???','java version':'???','fc_speed':'???','total_fc_ports':'???','total_fc_active':'???','host_bw_MB/s':'???','total_cpu':'???','total_memory':'???','iSCSI_10Gb':'???'}
	# need to edit print to look nice
	hosts_output=open("hosts_list_%s" %(list),"w")
	if sort == 'name':
		print "list of free hosts sorted by %s:" %(sort)		
		hosts_output.write("list of free hosts sorted by %s:\n" %(sort))
		for host_key in sorted(host_list_ok):
			print "*******************************************"
			hosts_output.write("*******************************************\n")
			print host_key
			hosts_output.write(host_key+'\n')
			for host_key_values in sorted(host_list_ok[host_key]):
				print host_key_values,host_list_ok[host_key][host_key_values]
#				hosts_output.write(host_key_values+'\t'+host_list_ok[host_key][host_key_values]+'\n')
				hosts_output.write(host_key_values+'\t')
#				hosts_output.write('\t')
				hosts_output.write(str(host_list_ok[host_key][host_key_values])+'\n')
#				hosts_output.write('\n')
#				hosts_output.write(host_list_ok[host_key][host_key_values]+'\n')
	else: 
		sort_dir={}
		print "list of free hosts sorted by %s:" %(sort)
		hosts_output.write("list of free hosts sorted by %s:\n" %(sort))
		for host_key in host_list_ok:
			sort_dir[host_key] = host_list_ok.get(host_key).get(sort)
		for key, value in sorted(sort_dir.iteritems(), key=lambda (k,v): (v,k)):
			print "host name:%s %s:%s" %(key, sort, value)
			hosts_output.write("host name:%s %s:%s\n" %(key, sort, value))
	hosts_output.close()
	#print free_host_list_ok
	print "list of no ping hosts:"
	print host_list_noping
	print "list of no ssh hosts:"
	print host_list_nossh
	return
			
# Define a main() function that prints a little greeting.
def main():
  # Aks the usr to select an option from the menu
  print "Please select your option:"
  print "1: List hosts info"
  print "2: List storage info"
  print "3: Allocate desired hosts"
  print "b: back"
  print "x: Exit"
  option = raw_input("Enter your option >>> ")
  exec_main(option)

#Execute selected menu  
def exec_main(option):
#    os.system('clear')
    selected_option = option.lower()
    if selected_option == '':
      print "No option was selected"
      menu_actions['main_menu']()
    else:
        try:
          menu_actions[selected_option]()
        except KeyError:
          print "Invalid selection, please try again.\n"
          menu_actions['main_menu']()
    return

# Back to main menu
def back():
  menu_actions['main_menu']()
 
# Exit program
def exit():
  sys.exit()

# host listing menus 
def list_hosts():
  print "\n"
  print "Please select your host list option:"
  print "1: List all hosts info"
  print "2: List Free hosts info"
  print "3: List hosts with no ping"
  print "4: List hosts with no ssh access"
  print "b: back"
  print "x: Exit"
  option = raw_input("Enter your option >>> ")
  menu=list_menu
  list_opt=exec_menu(menu,option)
  print "\n"
  print "Please select your host sort option:"
  print "1: Sort by host name"
  print "2: Sort by host FC speed"
  print "3: Sort by host total FC active"
  print "4: Sort by host total bw"
  print "b: back"
  print "x: Exit"
  option = raw_input("Enter your option >>> ")
  menu = sort_menu
  sort_opt=exec_menu(menu,option)
  hosts_info(list=list_opt,sort=sort_opt)
  print "\n"
  #print "b. Back"
  #print "x. Quit"
  #option = raw_input(" >>>  ")
  #exec_menu(option)
  return menu_actions['main_menu']()
 
def exec_menu(menu,option):
    selected_option = option.lower()
    if selected_option == '':
      print "No option was selected"
      menu['main_menu']()
    else:
        try:
		if selected_option.isdigit():
			return menu[selected_option]
		else:
			menu[selected_option]()
        except KeyError:
          print "Invalid selection, please try again.\n"
          menu['main_menu']()
    return 
 
# Menu definition
menu_actions = {
    'main_menu': main,
    '1': list_hosts,
    '2': "list_storage",  #to be developed
	'3': "allocate_hosts", #to be developed
    'b': back,
    'x': exit,
}

list_menu = {
    'main_menu': main,
    '1': "all",
    '2': "free",
	'3': "noping",
	'4': "nossh",
    'b': back,
    'x': exit,
}  

sort_menu = {
    'main_menu': main,
    '1': "name",
    '2': "fc_speed",
    '3': "total_fc_active",
    '4': "host_bw_MB/s",
    'b': back,
    'x': exit,
}  

# This is the standard boilerplate that calls the main() function.
if __name__ == '__main__':
  main()