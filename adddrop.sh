#!/bin/sh

numfun () {
echo "Choose a rule number >1000 that does not exist yet:"
read rule
if [ $rule -gt 999 ]; then
if [ $rule -lt 5000 ]; then
if [ -e /opt/vyatta/config/active/firewall/name/EXTERNAL/rule/$rule ]; then
        echo "That rule already exists."
        numfun
else
        echo "You have chosen $rule. Are you certain? Y/N"
        read answer
        if [ $answer != Y ]; then
                numfun
        else
                echo "You have chosen Rule# $rule"
        fi
fi
else
echo "You must choose a rule under 5000"
numfun
fi
else
echo "You must choose a rule number over 1000"
numfun
fi
}

ipfun () {
echo "Enter the IP you wish to block:"
read ip
if [[ `echo $ip | grep "\.0"` ]];
then
echo "You cannot specify an entire block. Use single IPs only"
ipfun
fi
echo "IP: $ip"
echo "Are you certain? Y/N"
read answerip
if [ $answerip != Y ]; then
ipfun
fi
}

descfun () {
echo "Type a description for this rule:"
read description
echo "Description: $description"
echo "Are you happy with this? Y/N"
read answerdesc
if [ $answerdesc != Y ]; then
descfun
fi
}

echo "Listing current DROP rules:"
/opt/vyatta/bin/vyatta-show-firewall.pl "all_all" /opt/vyatta/share/xsl/show_firewall_statistics.xsl | grep DROP | grep -v 10000
echo "-------
"



numfun
ipfun
descfun

echo "You will have to cut & paste the following lines after exiting this script:"



echo "
"
echo "configure"
echo "set firewall name EXTERNAL rule $rule action drop"
echo "set firewall name EXTERNAL rule $rule description \"$description\""
echo "set firewall name EXTERNAL rule $rule protocol tcp"
echo "set firewall name EXTERNAL rule $rule source address $ip"
echo "show firewall name EXTERNAL rule $rule"
echo "
"

echo "Then once you are *CERTAIN*, make it live with:"
echo "
"
echo "commit"
echo "save
"
echo "You may then exit this firewall and submit the same commands onto the other firewall."

