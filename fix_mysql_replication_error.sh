#!/bin/bash
#
# Event handler script for restarting a service on the local machine
#
#
LOCKFILE=/tmp/fix_mysql_replication_error
# This is the default error code we want to work on.
ERRCODE="1062"
# For skips, default to just 1 skip
TRIES=1
FORCE=0
DBSUPERPASS = ""
DBSUPERUSER = ""
DBUSER = ""
DBPASS = ""

if [ $# -lt 2 ]; then
        echo -e "\e[91mError: Needs more arguments\e[0m"
        echo -e "Usage: \e[1mfix_mysql_replication_error.sh -s [CRITICAL|WARNING|OK] -t [SOFT|HARD] [-m {master-conn}] [-c #] [-e #]\e[0m"
	echo -e "If you wish to use this on the command line, enter the first two arguments as if it was run by the Nagios event handler: ./fix_mysql_replication_error -s CRITICAL -t HARD [other arguments]"
        echo -e "\e[1m-s\e[0m : Required: Service state: CRITICAL, WARNING, or OK"
        echo -e "\e[1m-t\e[0m : Required: State Type: SOFT or HARD"
	echo -e "\e[1m-n\e[0m : Add this flag for the Nagios event handler. This will disable the prompts and send an email."
        echo -e "\e[1m-m\e[0m : The master connection name for multi-master setups."
        echo -e "\e[1m-c\e[0m : How many times should we try skipping? (only applicable for errors 1062, 1007, 1008)"
        echo -e "\e[1m-e\e[0m : Defaults to 1062. Use this flag to work on a different error code."
	echo -e "\e[1m-f\e[0m : Force the run, regardless of event_stop or lock files."
        exit 1;
fi



while getopts "s:t:nm:c:e:f" Option
do
        case $Option in
                s       ) STATE=$OPTARG;;
                t       ) TYPE=$OPTARG;;
		n	) NAGIOS=1;;
                m       ) MASTERCONN=$OPTARG;;
                c       ) TRIES=$OPTARG;;
                e       ) ERRCODE=$OPTARG;;
		f	) FORCE=1;;
        esac
done

shift $(($OPTIND -1))


# Does /tmp/event_stop exist? If so this script should exit without doing anything further.
if [[ $FORCE == 0 ]]; then
	if [ -e /tmp/event_stop ]; then
	  echo -e "\e[91m/tmp/event_stop file in place. This script will not run.\e[0m"
	  exit 0
	fi
fi

## This function will simply return the current SQL or IO error code
function get_sql_err() {
        SQLERR=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Last_SQL_Errno | sed -re 's/.*: //' )
	if [[ $SQLERR == 0 ]]; then
		IOERR=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Last_IO_Errno | sed -re 's/.*: //' )
		echo $IOERR
	else
		echo $SQLERR
	fi
        }
        
## This function will return the text of the current SQL or IO error
function get_sql_errmsg() {
	SQLERRMSG=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Last_SQL_Error | sed -re 's/.*SQL_Error: //' )
	if [[ $SQLERRMSG == "" ]]; then
		IOERRMSG=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Last_IO_Error | sed -re 's/.*SQL_Error: //' )
		echo $IOERRMSG
	else
		echo $SQLERRMSG
	fi
	}


## All of the below functions try to repair replication, and each is meant for different error codes.
## They each return the following possible results: success, failed, newerr, tryagain
## success: The replication is functioning now.
## failed: The exact same error message remains
## newerr: The original error was fixed, but a new type of error has appeared
## tryagain: The origial error was fixed, but a new error of the exact same type has appeared

## This function simple stops and restarts the replication, then checks the slave status, returning the result
function stop_start_slave() {
	mysql -u$DBSUPERUSER -p$DBSUPERPASS -e "stop slave $CONNNAME; start slave $CONNNAME"
	/usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT > /dev/null
	if [ $? -ne 0 ]; then
		ERRMSGNEW=$( get_sql_errmsg )
		if [[ $ERRMSGNEW == $ERRMSG ]]; then
                        echo "failed"
		else
			echo "newerr"	
		fi
	else
		echo "success"
	fi
	}

## This function resets the slave to the last position replicated. This is for error 1594 where the relay log is corrupted. It then checks the replication status and returns the result.
function reset_slave_info_1594() {
	CURLOGFILE=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Relay_Master_Log_File | sed -re 's/.*Relay_Master_Log_File: //' )
	CURLOGPOS=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Exec_Master_Log_Pos | sed -re 's/.*Exec_Master_Log_Pos: //' )
	mysql -u$DBSUPERUSER -p$DBSUPERPASS -e "stop slave $CONNNAME; $SETCONNECTIONCMD; change master $CONNNAME to master_log_file = '$CURLOGFILE', master_log_pos = $CURLOGPOS; start slave $CONNNAME"
	/usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT > /dev/null
	if [ $? -ne 0 ]; then
		ERRMSGNEW=$( get_sql_errmsg )
		if [[ $ERRMSGNEW == $ERRMSG ]]; then
                        echo "failed"
		else
			echo "newerr"	
		fi
	else
		echo "success"
	fi
	}

## This function skips replication to the next binlog file, position 4. This is designed for error 1236, which happens when the master has crashed and started a new binlog file without notifying the slave. It works by pulling the number off of the current binlog file, adding a "1" to the left of the number string, to make it easy to deal with the 0 padding, then adding 1 to the number, then removing the 1 again leaving only the 0 padding.
function reset_slave_info_1236() {
	CURLOGFILE=$( mysql -u$DBUSER -p$DBPASS -e "show slave $CONNNAME status\G" | grep Relay_Master_Log_File | sed -re 's/.*Relay_Master_Log_File: //' )
	FILENAME=$( echo $CURLOGFILE | sed -re 's/\..*//' )
	FILENUM=$( echo $CURLOGFILE | sed -re 's/.*\.//' | sed -re 's/^/1/' )
	NEWNUM=$( expr $FILENUM + 1 | sed -re 's/^1//' )
	NEWLOGFILE="$FILENAME.$NEWNUM"
	mysql -u$DBSUPERUSER -p$DBSUPERPASS -e "stop slave $CONNNAME; $SETCONNECTIONCMD; change master $CONNNAME to master_log_file = '$NEWLOGFILE', master_log_pos = 4; start slave $CONNNAME"
	/usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT > /dev/null
	if [ $? -ne 0 ]; then
		ERRMSGNEW=$( get_sql_errmsg )
		if [[ $ERRMSGNEW == $ERRMSG ]]; then
                        echo "failed"
		else
			echo "newerr"	
		fi
	else
		echo "success"
	fi
	}

	
## This function stops the slave, sets sql_slave_skip_counter to 1, and starts the slave again. It then checks the replication status and returns the result. This result set includes the "tryagain" status if the error code remains the same, but the message has changed, showing that there is more of the same error to be skipped.
function try_skip_err() {
	ERRNO=$( get_sql_err )
       	if [[ $ERRNO != $ERRCODE ]]; then
		echo "newerr"
	else
		mysql -u$DBSUPERUSER -p$DBSUPERPASS -e "stop slave $CONNNAME; $SETCONNECTIONCMD ;set global sql_slave_skip_counter = 1; start slave $CONNNAME"
		## Check to see if we were successful
		/usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT > /dev/null
		if [ $? -ne 0 ]; then
			## Get the new ERRMSG and compare to the last one
			ERRMSGNEW=$( get_sql_errmsg )
			if [[ $ERRMSGNEW == $ERRMSG ]]; then
				echo "failed"
			else
				ERRNO=$( get_sql_err )
	       	 		if [[ $ERRNO != $ERRCODE ]]; then
					echo "newerr"
				else
					echo "tryagain"
				fi
			fi
		else
			echo "success"
		fi
	fi
	}

# What state is the service in?
case "$STATE" in
  OK)
    # The service just came back up, so don't do anything...
    # Except remove the lock file if one is still hanging around from a failed attempt to fix.
    rm -f $LOCKFILE
    ;;
  WARNING)
    # We don't really care about warning states, since the service is probably still running...
    ;;
  UNKNOWN)
    # We don't know what might be causing an unknown error, so don't do anything...
    ;;
  CRITICAL)
    # Aha!  The service appears to have a problem - perhaps we should restart the service...
    # Is this a "soft" or a "hard" state?
    case "$TYPE" in
      SOFT)
        # Don't do anything until the service is in a "hard" state.
        ;;

      HARD)
        # The service has turned into a hard error and needs to be fixed.
        # Note: Contacts have already been notified of a problem with the service at this
        # point (unless you disabled notifications for this service)

        ## Make sure this script isn't already running
	if [[ $FORCE == 0 ]]; then
        	if [ -e $LOCKFILE ]; then
	          echo -e "\e[91mExiting because another instance of this script is already running.\e[0m"
		  echo "If you want to run this script anyway, use the -f flag to force it."
	          exit 1
	        else
	          ## Create lock file
	          touch $LOCKFILE
	        fi
	fi

        echo "Checking error..."
	## Is this a named connection? If so, set the extra args for the commands.
	if [[ $MASTERCONN ]]; then
		CONNNAME="'$MASTERCONN'"
		SETCONNECTIONCMD="set @@default_master_connection='$MASTERCONN'"
		NAGIOSCHECKEXT="--master-conn $MASTERCONN"
	fi
	ERRNO=$( get_sql_err )
        ## Check if the current error is the one specified on the command line
        if [[ $ERRNO == $ERRCODE ]]; then
        	## Get the error message for display
        	ERRMSG=$( get_sql_errmsg )
		ERRMSGS=$ERRMSG
        	echo -e "Error \e[91m$ERRNO: $ERRMSG\e[0m"
		# Check if this is one of the errors we know about, and ask for confirmation
		if [[ $ERRNO == "1062" || $ERRNO == "1007" || $ERRNO == "1008" ]]; then
			echo -e "\e[1mThis type of error usually means someone entered or deleted data directly on the slave. It should be safe to skip.\e[0m"
			echo -e "\e[1mAre you sure you want to skip this statement? (Y/n)\e[0m"
		elif [[ $ERRNO == "1236" ]]; then
			echo -e "\e[1mThis type error usually means the master crashed and started a new log file without notifying the slave. We should skip to the next master log file.\e[0m"
			echo -e "\e[1mAre you sure you want to do this? (Y/n)\e[0m"
		elif [[ $ERRNO == "1594" ]]; then
			echo -e "\e[1mThis type error usually means you have to reset the slave to the current position because the relay log got corrupted somehow.\e[0m"
			echo -e "\e[1mAre you sure you want to do this? (Y/n)\e[0m"
		elif [[ $ERRNO == "1205" ]]; then
			echo -e "\e[1mLock Wait Timeout usually means you can just stop/start replication to fix it.\e[0m"
			echo -e "\e[1mShould we try this? (Y/n)\e[0m"
		else 
			echo -e "\e[1mI don't know how to handle this error. Exiting.\e[0m"
			exit 1
		fi

		## Check if this is an event handler, and if so, skip the prompt for confirmation
		if [[ $NAGIOS != "1" ]]; then
			read answer
		else 
			echo "Event handler: Answering yes."
			answer="Y"
		fi

		if [[ $answer != "Y" ]]; then
			echo -e "\e[91mYou chose to do nothing. Exiting script.\e[0m"
			exit 0
		else
       	 		echo -e "\e[1mWe will try to fix this error...\e[0m"
	
			## For each type of error, run the funtion designed for it, and return the result
			if [[ $ERRNO == "1062" || $ERRNO == "1007" || $ERRNO == "1008" ]]; then
        			RESULT=$( try_skip_err )
			elif [[ $ERRNO == "1236" ]]; then
				RESULT=$( reset_slave_info_1236 )
			elif [[ $ERRNO == "1594" ]]; then
				RESULT=$( reset_slave_info_1584 )
			elif [[ $ERRNO == "1205" ]]; then
				RESULT=$( stop_start_slave )
			fi

			
       		 	if [[ $RESULT == "failed" ]]; then
				## If 'failed' was returned, the error message remains exactly the same.
        		  	echo -e "\e[91mThe attempted fix failed. The error message is unchanged.\e[0m"
				## Continue to send the email if this is an event handler
        		elif [[ $RESULT == "tryagain" ]]; then
				## If 'tryagain' was returned, the original error was skipped, and a new one of the same type (usually 1062) remains.
        		  	echo -e "\e[1mQuery skipped. There are more errors.\e[0m"
        		  	if [[ $TRIES -gt 1 ]]; then
					## If the option for multiple tries was given, iterate though the count
        		  		for i in `seq 2 $TRIES`; do
          					RESULT=$( try_skip_err )
          					if [[ $RESULT == "success" ]]; then
          						echo "Success"
							SKIPRESULT="The skip was a success"
							## This one fixed it, so breaking out of the for loop
          						break
          					elif [[ $RESULT == "tryagain" ]]; then
							## More of the same error remains. Adding the new errors to the $ERRMSGS variable to put in the email
							echo "Trying again..."
          						ERRMSG=$( get_sql_errmsg )
							echo -e "\e[91m$ERRMSG\e[0m"
							ERRMSGS="$ERRMSGS\n\n$ERRMSG"
          						continue
						elif [[ $RESULT == "newerr" ]]; then
							## A new type of error has repaired. We're going to stop now.
							ERRNONEW=$( get_sql_err )
        					  	ERRMSGNEW=$( get_sql_errmsg )
							echo -e "\e[1mSome errors were skipped, but a new error has appeared. We are stopping.\e[0m"
							echo -e "\e[91m$ERRNONEW: $ERRMSGNEW\e[0m"
							break
          					elif [[ $RESULT == "failed" ]]; then
							## The error remains exactly the same. Breaking out of the loop.
          						echo "Failed"
							break
          					fi
          				done
					## The loop is done, we tried as many times as allowed on the command line. Now check the current status of replication.
					/usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT > /dev/null
					if [[ $? -gt 0 ]]; then
						echo -e "\e[1mThere are more errors. You only chose to skip $TRIES.\e[0m"
						## Ask if we should remove the lock file if run on the command-line. The event handler will leave it in place to make sure we don't keep running.
						echo -e "\e[1mDo you want to remove the lock file? (Y/n)\e[0m"
						if [[ $NAGIOS != "1" ]]; then
							read answer
						else
							echo "Event handler: Answering no."
							answer="N"
						fi
               	 				if [[ $answer == "Y" ]]; then
							echo "Deleting $LOCKFILE"
							rm -f $LOCKFILE
						else
							echo "Leaving the lockfile in place. $LOCKFILE"
						fi
					else
						echo -e "\e[32mSuccess. Replication is repaired.\e[0m"
               	 				rm -f $LOCKFILE
					fi
          			else
					## We default to only skipping 1 error
          				echo -e "\e[1mThere are more errors. You only chose to skip 1.\e[0m"
					echo -e "\e[1mDo you want to remove the lock file? (Y/n)\e[0m"
					if [[ $NAGIOS != "1" ]]; then
						read answer
					else
						echo "Event handler: Answering no."
						answer="N"
					fi
          	     	 		if [[ $answer == "Y" ]]; then
						echo "Deleting $LOCKFILE"
						rm -f $LOCKFILE
					else
						echo "Leaving the lockfile in place. $LOCKFILE"
					fi
        	  		fi
		 	elif [[ $RESULT == "newerr" ]]; then
				## A new different type of error has appeared after fixing the first. We should stop.
				ERRNONEW=$( get_sql_err )
       			   	ERRMSGNEW=$( get_sql_errmsg )
				echo -e "\e[1mThe error was fixed, but a new error has appeared. We are stopping.\e[0m"
				echo -e "\e[91m$ERRNONEW: $ERRMSGNEW\e[0m"
		        elif [[ $RESULT == "success" ]]; then
				## Replication appears to be fixed.
       		   		echo -e "\e[32mSuccess. Replication is repaired.\e[0m"
       		 		## Clean up the lock file only if we were successful to keep this from running again.
        			rm -f $LOCKFILE
			else 
				## We have no idea.... something is wrong.
				echo -e "\e[91mUnknown result: The function returned something unexpected."
         		fi
		fi
        else
		## The current error message does not match the default or the one entered on the command-line. If this is the event handler, the error is not a 1062, so we're doing nothing.
        	echo -e "\e[91mThe current error is $ERRNO. If you wish to try to handle this error, specify \"-e $ERRNO\"\e[0m"
        	## Keeping the lock file in place so it doesn't keep trying to fix it.
		## Exit now so an email isn't sent.
		exit 1
        fi

        echo -e "\e[1mScript Finished\e[0m"

	## Now send an email. First check the current status for pasting into the email.
	if [[ $NAGIOS == 1 ]]; then
        	REPCHECK=$( /usr/lib64/nagios/plugins/pmp-check-mysql-replication-running -l $DBUSER -p $DBPASS $NAGIOSCHECKEXT )
		echo -e "$ERRMSGS\n\n$REPCHECK" | mail -s "Replication autofix attempted by Nagios on `hostname -s`" email@email.com 
	fi

        ;;
    esac
esac
exit 0

