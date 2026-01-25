#!/bin/sh
# /jffs/scripts/cloudflareddns.sh - dynamic dns updater module for Asus router running Asuswrt-Merlin (https://asuswrt.lostrealm.ca)
#				    updates A record for the host names provides as arguments as well as the MX record for each top host name
#
# Author:
#	Julien Bardi
#
# Version:
#	0.3
# Requires:
#	jq	-> opkg install jq (install entware to enable opkg), jq is sed for JSON, see https://stedolan.github.io/jq
#	curl
# Description:
#	copy to /jffs/scripts/cloudflareddns.sh
#	make executable (chmod +x)
#
# Changelog:
#	0.2:
#		- Simplified this thing to its most basic requirements (curl + logging)
#		- Now either returns 'good' or the result (no checking for cases -- the log was always more useful anyway!)
#	0.3
#		- determine recidA
#
# Based on Michael Wildman (http://mwild.me) and Brian Schmidt Pedersen (http://blog.briped.net) gratisdns.sh
#
# these variables are passed by the calling program
__USERNAME__="$(echo ${@} | cut -d' ' -f1)"		#username is your email
__PASSWORD__="$(echo ${@} | cut -d' ' -f2)"		#password is your cloudflare API key
__MYIP__="$(echo ${@}  | cut -d' ' -f3)"		#IP4 external IP address
shift;shift;shift;					#discard the first 3 arguments
list="$*"						#store the remaining arguments as the list of hostnames for which a A DNS entry is required
_Nb_Errors_=0
# try to install jq which is part of Entware, preinstalled as /usr/sbin/entware-setup.sh, see https://github.com/RMerl/asuswrt-merlin/wiki/Entware
JQ=`which jq`;
if [ ${#JQ} -lt 1 ]; then
        opkg update     1>/dev/null;
        opkg upgrade    1>/dev/null;
        opkg install jq 1>/dev/null;
fi

for __HOSTNAME__ in ${list}
do
#printf "%s\n" ${__HOSTNAME__}
#__HOSTNAME__="$(echo ${@} | cut -d' ' -f4)"		#hostname is the name (nas.example.com but could be sub.nas.example.com)

# additional parameters needed for CloudFlare
__ZONEID__="" 		#this is the zone id in Cloudflare for the zone with name"=__TOPHOSTNAME__. Leave "" to get it determined based on top host name
__TTL__="120"		# min value: 1 max value: 2147483647 Time to live for DNS record. Value of 1 is 'automatic'. Must be 1 without "" for MX record
__PROXIED__="false"	# valid values: (true,false) Whether the record is receiving the performance and security benefits of Cloudflare

log() {
	__LOGTIME__=$(date +"%b %e %T")
	if [ "${#}" -lt 1 ]; then
		false
	else
		__LOGMSG__="${1}"
	fi
	if [ "${#}" -lt 2 ]; then
		__LOGPRIO__=7
	else
		__LOGPRIO__=${2}
	fi
	logger -p ${__LOGPRIO__} -t "$(basename ${0})" "${__LOGMSG__}"					#log into system log
	printf "%s\n"  "${__LOGTIME__} $(basename ${0}) (${__LOGPRIO__}): ${__LOGMSG__}"
}

get_top_hostname() {
	echo ${1} | grep -E -o '[a-z]+\.[a-z]+$'		# "example.com" for ${1}="nas.example.com"
}

get_zoneid() {
	#list zones, see https://api.cloudflare.com/#zone-list-zones 
	local zoneid=$(echo $(curl -X GET  "https://api.cloudflare.com/client/v4/zones?name=${1}" -H "X-Auth-Email: ${2}" -H "X-Auth-Key: ${3}") | jq '.result?[].id' );
	echo ${zoneid//\"}
}

create_if_required_and_get_zoneid() {
	local zoneid=$(get_zoneid ${1} ${2} ${3})
	if ["${zoneid}" == "" ] ;then
		local _response_=$(curl -X POST  "https://api.cloudflare.com/client/v4/zones" -H "X-Auth-Email: ${2}" -H "X-Auth-Key: ${3}" \
                 -H "Content-Type: application/json" --data '{"name":"'${1}'"}')
		local zoneid=$(get_zoneid ${1} ${2} ${3})
		log "Updating ${1} required the creation of the zone ID ${zoneid}" 7
	fi
	echo ${zoneid}
}

get_recordid() {
	local recid=$(echo $(curl -X GET  "https://api.cloudflare.com/client/v4/zones/${1}/dns_records?type=${2}&name=${3}" -H "X-Auth-Email: $4" -H "X-Auth-Key: $5") | jq '.result?[].id');
	echo ${recid//\"}
}

# Determine top host name "example.com" for ${1}="nas.example.com"
__TOPHOSTNAME__=$(get_top_hostname ${__HOSTNAME__})

# Get Zone ID based on __TOPHOSTNAME__
__ZONEID__=$(create_if_required_and_get_zoneid ${__TOPHOSTNAME__} ${__USERNAME__} ${__PASSWORD__})
#log "__ZONEID__=${__ZONEID__}" 7

#/-- MX record (only for __TOPHOSTNAME__  and always with TTL=1)
if [ "${__TOPHOSTNAME__}" == "${__HOSTNAME__}" ]
then
	recidMX=$(get_recordid ${__ZONEID__} MX ${__TOPHOSTNAME__} ${__USERNAME__}  ${__PASSWORD__})
	#log "recidMX=${recidMX}" 7
	case ${recidMX} in
		'')	
		#add entry as it may not exist
		_response_=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/${__ZONEID__}/dns_records" \
		 -H "X-Auth-Email: ${__USERNAME__}" -H "X-Auth-Key: ${__PASSWORD__}" \
		 -H "Content-Type: application/json" --data '{"type":"MX","name":"'${__TOPHOSTNAME__}'","content":"'${__TOPHOSTNAME__}'","ttl":1,"priority":0,"proxied":false}') # priority must be set and be between 0 (highest) and 65535
		;;
		*)
		#https://api.cloudflare.com/#dns-records-for-a-zone-update-dns-record
		_response_=$(curl -X PUT "https://api.cloudflare.com/client/v4/zones/${__ZONEID__}/dns_records/${recidMX}" \
		 -H "X-Auth-Email: ${__USERNAME__}" -H "X-Auth-Key: ${__PASSWORD__}" \
		 -H "Content-Type: application/json" --data '{"type":"MX","name":"'${__TOPHOSTNAME__}'","content":"'${__TOPHOSTNAME__}'","ttl":1,"priority":0,"proxied":false}')
		;;
	esac
#log "_response_=${_response_}" 5
# Strip the success element from response json
__RESULT__=$(echo ${_response_}  | jq '.success' ) # return true or false
case ${__RESULT__} in
        'true')
                __STATUS__='good'                                               #just for the screen
                true
                ;;
        *)
		_Nb_Errors_=${_Nb_Errors_}+1
                __STATUS__=$(echo ${_response_}  | jq '.errors[].message' )   #just for the screen
                log "_response_=${_response_}" 5
                false
                ;;
esac
log           "${__STATUS__} for ${__HOSTNAME__} to ${__MYIP__} type MX, record ID ${recidMX}" 6

fi
#\--
	

#/-- A record
__TTL__="120"
#get the DNS records for the zone
recidA=$(get_recordid ${__ZONEID__} A ${__HOSTNAME__} ${__USERNAME__}  ${__PASSWORD__})
#log "recidA=${recidA}" 7
case ${recidA} in
	'')
	#find and delete the CNAME entry if any (as A and CNAME entries are mutually incompatible for a given hostname)
	_recidCNAME_=$(get_recordid ${__ZONEID__} CNAME ${__HOSTNAME__} ${__USERNAME__}  ${__PASSWORD__})
	if [${_recidCNAME_} != ''] ;then
		_response_=$(curl -X DELETE "https://api.cloudflare.com/client/v4/zones/${__ZONEID__}/dns_records/${_recidCNAME_}" -H "X-Auth-Email: ${__USERNAME__}" -H "X-Auth-Key: ${__PASSWORD__}")
	fi
	#add entry as it may not exist
	_response_=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/${__ZONEID__}/dns_records" \
	     -H "X-Auth-Email: ${__USERNAME__}" -H "X-Auth-Key: ${__PASSWORD__}" \
	     -H "Content-Type: application/json" --data '{"type":"A","name":"'${__HOSTNAME__}'","content":"'${__MYIP__}'","ttl":'${__TTL__}',"proxied":'${__PROXIED__}'}')
	;;
	*)
	#https://api.cloudflare.com/#dns-records-for-a-zone-update-dns-record
	_response_=$(curl -X PUT "https://api.cloudflare.com/client/v4/zones/${__ZONEID__}/dns_records/${recidA}" \
	     -H "X-Auth-Email: ${__USERNAME__}" -H "X-Auth-Key: ${__PASSWORD__}" \
	     -H "Content-Type: application/json" --data '{"type":"A","name":"'${__HOSTNAME__}'","content":"'${__MYIP__}'","ttl":'${__TTL__}',"proxied":'${__PROXIED__}'}')
	;;
esac
#\--

#log "_response_ (of PUT)=${_response_}" 5
# Strip the success element from response json
__RESULT__=$(echo ${_response_}  | jq '.success' ) # return true or false
case ${__RESULT__} in
	'true')		
		__STATUS__='good'						#just for the screen
		true
		;;
	*)
		_Nb_Errors_=${_Nb_Errors_}+1
		__STATUS__=$(echo ${_response_}  | jq '.errors[].message' )	#just for the screen
		log "_response_=${_response_}" 5
		false
		;;
esac
log           "${__STATUS__} for ${__HOSTNAME__} to ${__MYIP__} type A" 6

done

if [ ${_Nb_Errors_} -eq 0 ]; then
  /sbin/ddns_custom_updated 1
else
  /sbin/ddns_custom_updated 0
fi
