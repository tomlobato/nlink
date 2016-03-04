#!/usr/bin/ruby

# TODO
# read interfaces and tr_tables

require 'rubygems'
require 'mail'
require 'ipaddr'

DRY = false
DEBUG = true 

# CONF

SERVER="Server Name"
NOTIFY_MAILS = %w(infra@example.com)

@lan = {
    # from /etc/network/interfaces
    :ip => "10.0.0.254",
    :bitmsk => 24,
    :dev => "br0"
}

@links = [{
    # from /etc/iproute2/rt_tables
    :table => 'faster',
    # from /etc/network/interfaces
    :dev => "eth4",
    :ip => '192.168.30.2',
    :gw => '192.168.30.1',
    :bitmsk => 24,
    # nlink
    :weight => 1
},{
    :table => 'virtua',
    :dev => "eth2",
    :ip => '192.168.0.3',
    :gw => '192.168.0.1',
    :bitmsk => 24,
    :weight => 2
}]


# DEFS

LOGFILE='/var/log/nlinks/nlinks.log'
PIDFILE="/var/run/nlinks.pid"
PING_OPT=" -Q 0x10 -c 1 "
SPEC_ROUTE="/usr/local/sbin/specific_routes.sh"

TST_PRIO=30
SPEC_PRIO=70
MAIN_PRIO=100
LINKS_PRIO=200
LB_PRIO=300

BASE_TABLE=20
LB_TABLE=50

PERIOD=10
RETRIES=6
CHECK=0

TST_IPS = [
    '8.8.8.8',        # dns google
    '208.67.222.222', # dns opendns
    '200.176.2.10',   # dns terra
    '208.67.220.220', # dns opendns
    '8.8.4.4'         # dns google
]


# AUX FUNCS

def cidr2msk(cidr)
    IPAddr.new('255.255.255.255').mask(cidr).to_s
end

def log(str, to_console = false)
    begin
        puts str if to_console or DEBUG
        @log_h ||= File.open(LOGFILE,'a')
        @log_h.write(str+"\n")
	@log_h.flush
    rescue Exception => e
        puts "----#{__LINE__}----\n#{e.message}\n#{e.backtrace.join("\n")}"
    end
end

def notify(l)
    resource = l[:name]
    date = Time.now.strftime('%d/%m/%Y %T')
    status_name = l[:status] ? 'ONLINE' : 'OFFLINE'

    mail = Mail.new do
      from     'noreply@example.com'
      to       NOTIFY_MAILS
      subject  "#{SERVER} - #{resource} ewent #{status_name}#{(DEBUG ? ' (debug mode)':'')}"
      body     "
Link #{resource} went #{status_name} at #{date}hs.

IT
support@example.com

"
    end

    mail.delivery_method :sendmail
    mail.deliver
end

def shell(cmd)
    puts cmd if DEBUG
    return [0, ''] if DRY

    cmd="#{cmd} 2>&1"
    output = IO.popen(cmd, "r") {|pipe| pipe.read}
    case $?.exitstatus
    when 0
    else
        log "#####\nComando '#{cmd}' exited with status #{$?.exitstatus}.\nOutput:\n#{output}\n#####}"
    end

    if DEBUG
        puts $?.exitstatus
        puts output
    end

    [$?.exitstatus, output]
end

def daemonize_app
  if RUBY_VERSION < "1.9"
    exit if fork
    Process.setsid
    exit if fork
    Dir.chdir "/"
    STDIN.reopen "/dev/null"
    STDOUT.reopen "/dev/null", "a"
    STDERR.reopen "/dev/null", "a"
  else
    Process.daemon
  end
end

def do_exit
    log "Exiting now. Bye!"
    flush
    begin
        File.delete(PIDFILE)
    rescue Exception => e
        puts "Nlinks was stopped but had errors for delete pidfile #{PIDFILE}: #{e.message}"
	exit 1
    end
    exit
end

def got_sig_term
    unless @setting_default_route
        do_exit
    else
        @must_exit = true
    end
end


# FUNCS

def best_route_table
    @links.each{|l| return l[:table] if l[:status]}
    nil
end

def setrt(l)
    l[:tst].each do |tst|
        shell "ip rule add prio #{TST_PRIO} to #{tst} table #{l[:table]}"
    end
    shell "ip rule add prio #{LINKS_PRIO} from #{l[:net]}/#{l[:msk]} table #{l[:table]}"
 
    @links.each do
        shell "ip route add #{l[:net]}/#{l[:msk]} dev #{l[:dev]} src #{l[:ip]} table #{l[:table]}"
    end

    shell "ip ro add #{@lan[:net]}/#{@lan[:msk]} dev #{@lan[:dev]} table #{l[:table]}"
    
    shell "ip ro replace default via #{l[:gw]} dev #{l[:dev]} src #{l[:ip]} proto static table #{l[:table]}"
    shell "ip ro append prohibit default table #{l[:table]} metric 1 proto static"
end

def unsetrt(l)
    l[:tst].each do |tst|
        shell "ip rule del prio #{TST_PRIO} to #{tst} table #{l[:table]}"
    end
    shell "ip rule del prio #{LINKS_PRIO} from #{l[:net]}/#{l[:msk]} table #{l[:table]}"
    shell "ip route flush table #{l[:table]}"
end

def flush
    log "Flushing rules/routes..."

    shell "ip rule del prio #{MAIN_PRIO} table main 2> /dev/null"

    @links.each{|l| unsetrt l}

    shell "ip rule del prio #{LB_PRIO} table #{LB_TABLE}"
    shell "ip route flush table #{LB_TABLE}"

    shell "#{SPEC_ROUTE} flush prio=#{SPEC_PRIO}"
end
 
def set_default_route
    @setting_default_route = true
    
    if @links.map{|l| l[:status]?1:0}.inject(:+) == 1
        @links.each do |l|
            if l[:status]
                shell "ip route replace default via #{l[:gw]} dev #{l[:dev]}"
                shell "#{SPEC_ROUTE} table=#{l[:table]} prio=#{SPEC_PRIO}"
                break
            end
        end
    else
        hops = ''
        @links.each do |l|
            hops = "#{hops} nexthop via #{l[:gw]} dev #{l[:dev]} weight #{l[:weight]}" if l[:status]
        end
	table = best_route_table
	if table.nil?
            shell "#{SPEC_ROUTE} flush prio=#{SPEC_PRIO}"
	else
            shell "#{SPEC_ROUTE} table=#{table} prio=#{SPEC_PRIO}"
	end

        shell "ip route del default"
        shell "ip route replace default table #{LB_TABLE} proto static #{hops}"
    end

    @setting_default_route = false
end

def setroutes
    log "Setting routes..."
    shell "ip rule add prio #{MAIN_PRIO} table main"
    shell "ip route del default table main 2> /dev/null"
    shell "ip route flush table #{LB_TABLE} 2> /dev/null"

    @links.each{|l| setrt l}

    shell "ip rule add prio #{LB_PRIO} table #{LB_TABLE}"
    set_default_route
end

def get_rtt(output)
    output.each_line do |l|
        if l =~ / time=([^ ]*) ms/
            return $1
        end
    end
    ""
end

def check(l)
    retval = 0; output = ""

    l[:tst].each do |tst_ip|
        retval, output = shell "eval ping #{PING_OPT} -I #{l[:dev]} #{tst_ip}"
	break if retval == 0
    end

    l[:no_pong_count] ||= 0

    if retval == 0
        l[:no_pong_count] = 0
        l[:rtt] = "rtt=#{get_rtt(output)}"
    else
        l[:no_pong_count] += 1
        l[:rtt] = 'failed'
    end

    l[:status] = l[:no_pong_count] < RETRIES
end

def start_loop
    log "Daemonizing..."
    daemonize_app

    begin
        File.open(PIDFILE, 'w'){|f| f.write($$)}
    rescue Exception => e
	log "Was not able to write pid file (#{PIDFILE}): #{e.message}"
    end

    log "#{Time.now.strftime('%d/%m/%Y %T')}: starting loop"

    while true
        newstatus = ""
        @links.each do |l|
            oldstatus = l[:status]

            check l
            
            if oldstatus != l[:status] 
                notify l
            end
            
            newstatus = "#{newstatus}#{l[:status]?1:0}"
        end

        @links.each do |l|
            log "@@@@ #{l[:name]} (#{l[:ip]}): #{l[:status]?'OK':'INATIVO'} #{l[:rtt]}" 
        end

        @linkstatus ||= (1..@links.size).map{1}.join

        if @linkstatus != newstatus
            log "#{Time.now.strftime('%d/%m/%Y %T')}: #{@linkstatus} > #{newstatus}"
            set_default_route
	    do_exit if @must_exit
        end

        @linkstatus = newstatus

	if DEBUG
	    puts "_________________________________"
	    puts @links.to_yaml
	    puts "_________________________________"
	end

        sleep PERIOD
    end
end

def popul_links
    @links.each do |l|
        l[:net] = IPAddr.new(l[:ip]).mask(l[:bitmsk]) 
        l[:msk] = cidr2msk l[:bitmsk]
        l[:name] = l[:table].capitalize
        l[:weight] ||= 1
        l[:status] ||= true
    end
    
    tst_ip_per_link = (TST_IPS.size.to_f / @links.size).floor
    if tst_ip_per_link == 0
        log "Ips de teste insuficientes. Abortando."
        exit 1
    end
    i = -1
    @links.each do |l|
        l[:tst] = []
        (1..tst_ip_per_link).each do
            l[:tst] << TST_IPS[ i+=1 ]
        end
    end
    
    @lan[:net] = IPAddr.new(@lan[:ip]).mask(@lan[:bitmsk])
    @lan[:msk] = cidr2msk @lan[:bitmsk]
end

def iptables_mangle_forward
    shell "iptables -t mangle -F"
    shell "iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark"
    @links.each_with_index do |l, idx|
        shell "iptables -t mangle -A FORWARD -m mark --mark 0 -o #{l[:dev]} -j MARK --set-mark 0x#{idx+1}"
        shell "iptables -t mangle -A FORWARD -m mark --mark 0 -i #{l[:dev]} -o #{@lan[:dev]} -j MARK --set-mark 0x#{idx+1}"
    end
    shell "iptables -t mangle -A FORWARD -j CONNMARK --save-mark"
end

def iptables_nat_postrouting
    @links.each do |l|
        shell "iptables -t nat -A POSTROUTING -s #{@lan[:net]}/#{@lan[:bitmsk]} -o #{l[:dev]} -j SNAT --to #{l[:ip]}"
    end
end


# Let's work!

Signal.trap("TERM") do
    got_sig_term
end

case ARGV[0]
when "iptables_mangle_forward"
    popul_links
    iptables_mangle_forward

when "iptables_nat_postrouting"
    popul_links
    iptables_nat_postrouting 

when "stop"
    pid = File.open(PIDFILE){|f| f.read}.to_i rescue nil
    if pid.nil? or pid.to_s !~ /^\d+$/
        log "Pid is wrong or cannot be read from #{PIDFILE}."
	exit 1
    else
	begin
            Process.kill("TERM", pid)
	rescue Exception => e
            puts e.message
	    exit 1
	end
    end

when "start", nil
    popul_links
    setroutes
    start_loop

else
    puts "syntax: nlinks [start|stop|iptables_mangle_forward|iptables_nat_postrouting]\nwithout arguments, it assumes \"start\"."
    exit 1
end


