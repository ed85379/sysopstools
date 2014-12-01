#!/bin/sh

while getopts "bas:e:l:" Option
do
        case $Option in
		b	) BING=1;;
		a	) AURORA=1;;
                s       ) STARTTEXT=$OPTARG;;
                e       ) ENDTEXT=$OPTARG;;
                l       ) LOGNUM=$OPTARG;;
        esac
done

HELP="Usage: ./top15ips.sh [-b -a] -s \"start time\" -e \"end time\" [-l #]
\nThe start time and end time fields can be any clear descriptive time.
\neg. \"20 minutes ago\", \"now\", \"4/11/2012 13:40\"
\nThe -l argument is used if you need to look at a previous day's log.
\neg. 1 = yesterday, 2 = two days ago, etc up to 7.
\n-b and -a are to include BingBot and Auroa IPs in the results, respectively."

if [[ $STARTTEXT ]]; then
	STARTDATE=`date -d "$STARTTEXT" +%d/%b/%Y:%H:%M:%S`
else
	echo "Invalid number of arguments"
	echo -e $HELP
exit
fi

if [[ $ENDTEXT ]]; then
	ENDDATE=`date -d "$ENDTEXT" +%d/%b/%Y:%H:%M:%S`
else
	echo "Invalid number of arguments"
	echo -e $HELP
exit
fi

if [[ $BING == "1" ]]; then
	BINGTEXT="?"
else
	BINGTEXT="157.*.*.*" 
fi
if [[ $AURORA == "1" ]]; then
	AURORATEXT="?"
else
	AURORATEXT="76.7.85.110" 
fi


BASEFILENAME="/var/log/httpd/www.tributes.com-access_log"
if [[ $LOGNUM ]]; then
	FILENAME=$BASEFILENAME.$LOGNUM
else
	FILENAME=$BASEFILENAME
fi

STARTLINE=`grep -m1 -n "$STARTDATE" $FILENAME`
if [ $? != 0 ]; then echo "Start date does not exist in the file"; exit; fi
ENDLINE=`grep -m1 -n "$ENDDATE" $FILENAME`
if [ $? != 0 ]; then echo "End date does not exist in the file"; exit; fi

LINE1=`echo $STARTLINE | sed -re 's/([0-9]+):.*/\1/'`
LINE2=`echo $ENDLINE | sed -re 's/([0-9]+):.*/\1/'`
EOF=`cat $FILENAME | wc -l`

LINEDIFF=$(($LINE2-$LINE1))
EOFDIFF=$(($EOF-$LINE1))

tail -n $EOFDIFF $FILENAME | head -n $LINEDIFF | sed -re 's/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) .*/\1/' | sort | grep -v "$BINGTEXT" | grep -v "$AURORATEXT" | uniq -c | sort -g | tail -n 15
