#!/bin/sh

# Publish.sh
# Version 0.9.3 beta
# This script will push code and then restart the production servers.

VERSION="0.9.3 beta"

# Set some defaults:
APACHE=0
PROMPT=0
CONTINUE=0
WAIT=5
RESTART=1
DRYRUN=" "
BYPASS=0
HELP=0
ONLYRESTART=0
SHOW=1

PRODCODEDIR="/opt/app/release_03_rails_update"
STAGINGCODEDIR="/opt/app/release_03"
STAGINGSHAREDCODEDIR="/ops/releases/release_03_rails_update"
#PRODCODEDIR="/opt/app/testrails"
#STAGINGCODEDIR="/opt/app/testrails"
#STAGINGSHAREDCODEDIR="/ops/releases/testrails"

# Setup the options:
while getopts "dw:af:cphrsy" Option
do
        case $Option in
                d       ) DRYRUN="--dry-run";RESTART=0;;
                w       ) WAIT=$OPTARG;;
                a       ) APACHE=1;;
                f       ) FILE=$OPTARG;;
                c       ) CONTINUE=1;;
                p       ) RESTART=0;;
                h       ) HELP=1;;
                r       ) ONLYRESTART=1;;
                s       ) SHOW=0;;
                y       ) BYPASS=1;;
        esac
done
shift $(($OPTIND -1))

# Write some functions

# Some display/ansi functions
function info_text() {

        # Yellow. No hash.
        if [[ $1 == "prompt" ]]; then
                echo -e "\e[93m$2\e[0m"

        # Yellow. No return. No hash.
        elif [[ $1 == "prompt_wait" ]]; then
                printf "\e[93m$2\e[0m"

        # Red with hash.
        elif [[ $1 == "error" ]]; then
                echo -e "# \e[91m$2\e[0m"

        # Red without hash
        elif [[ $1 == "error_status" ]]; then
                echo -e "\e[91m$2\e[0m"

        # Red with hash. No return.
        elif [[ $1 == "error_wait" ]]; then
                printf "# \e[91m$2\e[0m"

        # No color. No hash.
        elif [[ $1 == "normal" ]]; then
                echo -e "$2"

        # No color. No return. No hash.
        elif [[ $1 == "normal_wait" ]]; then
                printf "$2"

        # No color with hash
        elif [[ $1 == "message_normal" ]]; then
                echo -e "# $2"

        # Bold with hash.
        elif [[ $1 == "message_bold" ]]; then
                echo -e "# \e[1m$2\e[0m"

        # Green. No hash.
        elif [[ $1 == "ok_status" ]]; then
                echo -e "\e[92m$2\e[0m"
        fi
}

# stat_file will just print out some info about each file sent to it
function stat_file() {
        stat --printf="# \e[92m%n\e[0m\\n# File Size: %sb\\n# Owner: %U Group: %G\\n# Last modified: %y\\n# \\n" $STAGINGCODEDIR/$1
}

# rsync will run rsync commands
function rsync_fun() {
        echo -e "\e[2mDEBUG: rsync -avi $1 --delete-after --exclude newrelic.yml --exclude .xml --exclude .svn --exclude 'tmp' --exclude 'log'  $ST
AGINGCODEDIR/$2 $STAGINGSHAREDCODEDIR/$2\e[0m"
        rsync -avi $1 --delete-after --exclude .xml --exclude 'newrelic.yml' --exclude .svn --exclude 'tmp' --exclude 'log'  $STAGINGCODEDIR/$2 $ST
AGINGSHAREDCODEDIR/$2
}


# Hashcheck verifies the files were transfered to production properly
hashcheck () {
        result=$(md5deep -x /opt/tributes/shared/$1-hashes.txt -r $STAGINGSHAREDCODEDIR/*)
        if [[ $? == 3 ]]; then
                if [[ $(md5deep -x /opt/tributes/shared/$1-hashes.txt -r /opt/app//$checkfile| grep -c -v "/log/") > 0 ]]; then
                        info_text error "Error: Some files are missing."
                        echo $result | sed -re 's/ /\n/g' | grep -v "/log/"
                        if [[ $CONTINUE == 0 ]]; then
                                info_text error "[FAIL] PANIC QUIT!"
                                exit 1
                        else
                                info_text error_status "[FAIL]"
                                info_text message_bold "Files missing, but continuing anyway, because of the -c flag."
                        fi
                else
                        info_text ok_status "[OK]"
                fi
        else
                info_text ok_status "[OK]"
        fi
}

# is_int checks if what is sent to it is a positive interger or not
function is_int() { return $(test "$@" -gt "0" > /dev/null 2>&1); }

# Check if the -h option was given, and print the help document
if [[ $HELP == 1 ]]; then
        printf "
publish.sh version $VERSION
Copyright (C) 2014-2015 by Ed Thomas

publish.sh is designed to publish new Rails code to the production servers.

Usage: publish.sh [OPTIONS]

Options
        -d      Run as Dry-run only. Will show which files will be rsynced, but nothing else.
        -w      The time in seconds to wait between each Rails or Apache restart.
        -a      Restart Apache instead of Rails. Will use 'graceful' restarts.
        -f      To push individual files rather than all, enclose files in quotes, relative to $STAGINGCODEDIR/
        -c      The script will continue past any file verification errors.
        -p      Push-only. The servers will not be restarted.
        -r      Restart-only. Nothing will be pushed. Works with the -a flag only.
        -s      Don't show files that will be pushed before rsyncing all. Just do it.
        -h      This help file. Will ignore all other flags, and only print this help.
"
        exit 0
fi


# Check the WAIT option for errors first
if [[ $WAIT ]]; then
        if $(is_int "${WAIT}"); then
                continue
        else
                info_text error "The WAIT time is not a positive integer."
                exit 1
        fi
fi

# Start the script and present the chosen settings
info_text normal "##############################################"
info_text normal "# \e[1mWelcome to the Tributes.com Publish Script\e[0m #"
info_text normal "# This script will sync the files from       #"
info_text normal "# Staging to the Production servers and then #"
info_text normal "# restart either Rails or Apache             #"
info_text normal "# For help, run with the -h flag.            #"
info_text normal "##############################################"
info_text message_bold "Your selected settings:"
if [[ $ONLYRESTART  == 1 ]]; then
        info_text message_bold "The servers will be restarted. Nothing will be pushed."
        if [[ $APACHE == 1 ]]; then
                info_text message_bold "You have chosen to restart Apache."
        else
                info_text message_bold "You have chosen to restart Rails."
        fi
        info_text message_bold "Wait time between restarts: ${WAIT}s"
else
        if [[ $FILE ]]; then
                info_text message_bold "Files: $FILE"
        else
                info_text message_bold "Files: All"
        fi
        if [[ $RESTART == 0 ]]; then
                info_text message_bold "You have chosen not to restart the servers."
        else
                if [[ $APACHE == 1 ]]; then
                        info_text message_bold "You have chosen to restart Apache."
                else
                        info_text message_bold "You have chosen to restart Rails."
                fi
                info_text message_bold "Wait time between restarts: ${WAIT}s"
        fi
        if [[ $CONTINUE == 1 ]]; then
                info_text message_bold "You have chosen to continue on file check error."
        fi
        if [[ $BYPASS == 1 ]]; then
                info_text message_bold "You have chosen to bypass prompts."
        fi
        if [[ $DRYRUN != " " ]]; then
                info_text message_bold "This will be a DRY-RUN only. Nothing will be pushed."
        fi
fi
info_text normal "##############################################"
info_text prompt "Press Enter to continue, or cancel with Ctrl-C..."
read answer






# Get the file option and parse it
# If files are specified, parse and run rsync to local folder for each
# else, run rsync once. $FILE remains blank, which is correct.
if [[ $ONLYRESTART == 0 ]]; then
        if [[ $FILE ]]; then
                for i in $FILE
                        do
                        if [ -e "$STAGINGCODEDIR/$i" ]; then
                                stat_file $i
                        else
                                info_text error_wait "The file does not exist: "
                                echo "$STAGINGCODEDIR/$i"
                                exit 1;
                        fi
                done
                info_text prompt_wait "Push these file(s)? Y/N "
                read answer
                if [[ $answer != "Y" ]]; then
                        info_text error "Canceling publish!"
                        exit 1
                else
                        info_text normal "##############################################"
                        info_text message_bold "Syncing Staging files to Shared Folder $STAGINGSHAREDDIR..."
                        info_text normal "##############################################"
                        for i in $FILE
                                do
                                rsync_fun "$DRYRUN" $i
                        done
                fi
        else
                if [[ $SHOW  == 1 ]]; then
                        # Generate hashes for check
                        info_text normal "##############################################"
                        info_text message_bold "Here are the files that will be pushed..."
                        info_text normal "##############################################"
                        md5deep -q -r $STAGINGSHAREDCODEDIR/* > /opt/tributes/shared/staging-hashes.txt
                        md5deep -x /opt/tributes/shared/staging-hashes.txt -r $STAGINGCODEDIR/* | grep -v "/log/" | grep -v "/tmp/"
                        info_text prompt_wait "Continue publish? Y/N "
                        read answer
                        if [[ $answer != "Y" ]]; then
                                info_text error "Canceling publish!"
                                exit 1
                        else
                                info_text normal "##############################################"
                                info_text message_bold "Syncing Staging files to Shared Folder $STAGINGSHAREDDIR..."
                                info_text normal "##############################################"
                                rsync_fun "$DRYRUN" $FILE
                        fi
                else
                        info_text normal "##############################################"
                        info_text message_bold "Syncing Staging files to Shared Folder $STAGINGSHAREDDIR..."
                        info_text normal "##############################################"
                        rsync_fun "$DRYRUN" $FILE

                fi
        fi
fi



# Time to rsync to the production machines
if [[ $ONLYRESTART == 0 ]]; then
        if [[ $DRYRUN == "--dry-run" ]]; then
                info_text normal "##############################################"
                info_text message_bold "DRY-RUN. Not syncing to Prod."
                info_text normal "##############################################"
        else
                info_text normal "##############################################"
                info_text message_bold "Creating rollback directories..."
                info_text normal "##############################################"
                webdo.sh -sq "/opt/app/rotate_rollback.sh"
                info_text normal "##############################################"
                info_text message_bold "Syncing to Production..."
                info_text normal "##############################################"
                echo -e "\e[2mDEBUG: webdo.sh \"rsync -avie  ssh root@web5:$STAGINGSHAREDCODEDIR /opt/app; rsync -avi   --delete-after --exclude ne
wrelic.yml --exclude 'tmp' --exclude 'log' --exclude 'public'   -e  ssh root@web5:$STAGINGSHAREDCODEDIR /opt/app;\"\e[0m"
                webdo.sh -w 1 "rsync -avie  ssh root@web5:$STAGINGSHAREDCODEDIR /opt/app; rsync -avi   --delete-after --exclude 'newrelic.yml' --ex
clude 'tmp' --exclude 'log' --exclude 'public'   -e  ssh root@web5:$STAGINGSHAREDCODEDIR /opt/app;"
        fi

        # Now verify that all of the files made it
        info_text normal "##############################################"
        info_text message_bold "Generating hashs to verify files..."
        info_text normal "##############################################"
        webdo.sh -s "printf \"Building hashes on \$(hostname -s).... \";md5deep -q -r $PRODCODEDIR/* > /opt/tributes/shared/\$(hostname -s)-hashes.
txt;echo -e \"\e[92m[DONE]\e[0m\""
        for host in web2 web3 web4 web7 web8 web1; do
                info_text normal_wait "Checking files on $host... "
                hashcheck $host
        done
fi
# Finally, we restart rails or apache
if [[ $RESTART == 0 ]]; then
        info_text normal "##############################################"
        info_text message_bold "NOT RESTARTING RAILS OR APACHE due to the -p or -d flags."
        info_text normal "##############################################"
else
        if [[ $APACHE == 1 ]]; then
                info_text normal "##############################################"
                info_text message_bold "Restarting Apache with graceful..."
                info_text normal "##############################################"
                echo -e "\e[2mDEBUG: webdo.sh -w $WAIT \"service httpd graceful\"\e[0m"
                # This is a one-off to make sure web3 keeps reporting to newrelic
                webdo.sh -s -h web3 "rm -f /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h web3 "cp /opt/app/current/config/newrelic-web3.yml /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h feeds "rm -f /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h feeds "cp /opt/app/current/config/newrelic-feeds.yml /opt/app/current/config/newrelic.yml"
                webdo.sh -w $WAIT "service httpd graceful"
        else
                info_text normal "##############################################"
                info_text message_bold "Restarting Rails..."
                info_text normal "##############################################"
                if [[ $FILE ]]; then
                        PUSH="Mini 'Mini Push'"
                else
                        PUSH="Full 'Full Push'"
                fi
                echo -e "\e[2mDEBUG: webdo.sh -w $WAIT \"cd $PRODCODEDIR; ruby $PRODCODEDIR/vendor/plugins/newrelic-rpm-032ddf2/bin/newrelic deploy
ment -e production -u $PUSH;  touch $PRODCODEDIR/tmp/restart.txt;\"\e[0m"
                # This is a one-off to make sure web3 keeps reporting to newrelic
                webdo.sh -s -h web3 "rm -f /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h web3 "cp /opt/app/current/config/newrelic-web3.yml /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h feeds "rm -f /opt/app/current/config/newrelic.yml"
                webdo.sh -s -h feeds "cp /opt/app/current/config/newrelic-feeds.yml /opt/app/current/config/newrelic.yml"
                webdo.sh -w $WAIT "cd $PRODCODEDIR; ruby /opt/ruby-enterprise-1.8.7-2012.02/lib/ruby/gems/1.8/gems/newrelic_rpm-3.9.9.275/bin/newre
lic deployment -e production -u $PUSH;  touch $PRODCODEDIR/tmp/restart.txt;"
        fi
fi
