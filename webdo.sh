#!/bin/sh

if [ $# -lt 1 ]; then
	echo "Error: Needs more arguments"
	echo "Usage: webdo.sh [-s] [-q] [-w #] [-h \"list of hosts\"] <command>"
	exit 1;
fi

SILENT=0
QUIT=1
HOSTS="web2 web3 web4 web7 web8 feeds"

while getopts "sqh:w:" Option
do
	case $Option in
		s	) SILENT=1;;
		q	) QUIT=0;;
		h	) HOSTS=$OPTARG;;
		w	) WAIT=$OPTARG;;
	esac
done

shift $(($OPTIND -1))

COMMAND=$1

function is_int() { return $(test "$@" -gt "0" > /dev/null 2>&1); }
if [[ $WAIT ]]; then
	if $(is_int "${WAIT}"); then
		if [ $SILENT -ne 1 ]; then echo "====Waiting $WAIT seconds between each server===="; fi
	else
		echo "The WAIT time is not a positive integer"
		exit 1
	fi
fi


for i in $HOSTS
do
if [ $SILENT -ne 1 ]; then echo "==== RESULTS FROM $i ===="; fi
ssh $i "$COMMAND"
if [[ $? -ne 0 && $QUIT -eq 1 ]]
then
echo "Non-zero return from $i. QUITING"
exit 1
fi
if [ $SILENT -ne 1 ]; then echo "==== END RESULTS $i ===="; fi
if [ $SILENT -ne 1 ]; then echo ""; fi
if [[ $WAIT -gt 0 && $SILENT -ne 1 ]]; then echo "==== Waiting for $WAIT seconds ===="; fi
if [[ $WAIT -gt 0 ]]; then sleep $WAIT; fi
done


exit $?
		
