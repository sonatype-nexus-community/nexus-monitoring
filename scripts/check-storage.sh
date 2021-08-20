#!/bin/bash

# Script to check Nexus data.dir and BlobStore Filesystem usage
# Expected to be schduled to run on Nexus node.

NEXUS_URL="http://localhost:8081"
NEXUS_CREDENTIALS="admin:admin123" # update nexus credentials
ALERTSIZE=104857600 # Checks for min 100GB free
ALERTPCT=80  # Checks for more than 80% usage
ALERTMAILID="root@localhost"

f_check_access () {
   if curl -sk "${NEXUS_URL}" | grep "Nexus Repository" > /dev/null ; then
      if [ `curl -sk -i -u ${NEXUS_CREDENTIALS} "${NEXUS_URL}/service/rest/v1/status" | grep ^HTTP | cut -f2 -d" "` != 200 ] ; then
         echo "Access Denied: Check provided credentials" ; exit
      fi
   else
     echo "Check if Nexus is running on provided URL"  ; exit
  fi
}



f_get_datadir () {
  datadir=`curl -sk -X GET  "${NEXUS_URL}/service/rest/atlas/system-information" -H 'accept: application/json' -u ${NEXUS_CREDENTIALS} | grep -w karaf.data | grep -v uri | cut -d"\"" -f4 | uniq`
  mnts=($(stat -c%m $datadir))
}

f_get_blobs() {
  for fileblobs in `curl -s -u ${NEXUS_CREDENTIALS} -X GET -H 'accept: application/json' "${NEXUS_URL}/service/rest/v1/blobstores"| egrep '"name" :|"type" :' | paste - - | grep -w '"type" : "File"' | cut -
d"\"" -f4` ; do
   for paths in `curl -s -u ${NEXUS_CREDENTIALS} -X GET -H 'accept: application/json' "${NEXUS_URL}/service/rest/v1/blobstores/file/$fileblobs" | grep '"path"' | cut -d"\"" -f4` ; do
     if [ `echo $paths |cut -c1 ` != "/" ] ; then paths=$datadir/blobs/$paths ;fi
     mnts+=($(stat -c%m $paths))
   done
  done
}

f_check_usage () {
  read -r freespace usedpct <<< $(df $1 --output=avail,pcent|grep -v Avail|sed 's/\%//')
  if [ $freespace -lt $ALERTSIZE ] || [ $usedpct -gt $ALERTPCT ] ;then
   echo "ALERT : Nexus Blob Filesystem Usage "
   if [ $usedpct -gt $ALERTPCT ] ; then echo "Filesystem $1 usage is more than $ALERTPCT%" ; fi
   if [ $freespace -lt $ALERTSIZE ] ; then echo "Filesystem $1 has less than $((ALERTSIZE/1024/1024))GB free space" ; fi
  fi
}

f_send_email() {
  if [[ -x /usr/bin/mailx ]] && [ -s /tmp/checkstorage-alerts.txt ] ; then
     mailx -s "ALERT : Nexus Blob Filesystem Usage" $ALERTMAILID < /tmp/checkstorage-alerts.txt
     rm -f /tmp/checkstorage-alerts.txt
  fi
}

# Main

f_check_access
f_get_datadir
f_get_blobs

# Check if mount points are detected
if [[ ${#mnts[@]} == 0 ]] ; then echo "No FileSystem Mounts found, Exiting..." ; exit ; fi

for fs in `tr ' ' '\n' <<< "${mnts[@]}" | sort -u`; do
 f_check_usage $fs
done > /tmp/checkstorage-alerts.txt

f_send_email
