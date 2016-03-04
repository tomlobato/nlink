#! /bin/sh
#exit

### BEGIN INIT INFO
# Provides:		nlinks
# Default-Start:	2 3 4 5
# Default-Stop:		
# Short-Description:	Nlinks
### END INIT INFO

set -e

DAEMON="/usr/local/sbin/nlinks"

test -x $DAEMON || exit 0

. /lib/lsb/init-functions

case "$1" in
  start)
	log_daemon_msg "Starting Nlinks"
	$DAEMON start
        [ $? -ne 0 ]&& {
	    echo "Erro ao iniciar nlinks."
	    exit 1
        }
	;;

  stop)
	log_daemon_msg "Stopping Nlinks"
        $DAEMON stop
        [ $? -ne 0 ]&& {
	    echo "Erro ao parar nlinks."
	    exit 1
        }
	;;

  restart)
	log_daemon_msg "Restarting Nlinks"
	$DAEMON stop
	$DAEMON start
	;;

    *)
	log_action_msg "Usage: $0 {start|stop|restart}"
	exit 1
esac

exit 0
