#!/bin/sh

#wget -O - https://s3.amazonaws.com/shrepo/CodeSyncAuto.sh | bash

# Needs $fud exported from CFN script user data

cat << EOF > /usr/local/bin/Deploy
#!/bin/sh

sendErrorToSQS(){
  # Set region
  local AWS_REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
  # Set AccountId
  local ACCOUNT_ID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk '{ print $3 }' | tr -d [', "']`
  local topicARN="arn:aws:sns:$AWS_REGION:$ACCOUNT_ID:CloudwatchTopic"

  local err=$1
  local TIMESTAMP=`date -u +%Y-%m-%dT%H:%M:%S.000Z`
  local INSTANCEID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep "instanceId" |awk -F\" '{print $4}'`
  local msg="{\"AlarmName\":\"Deploy script failure\",\"AlarmDescription\":\"AWS account: $ACCOUNT_ID, instance ID: $INSTANCEID, issue: $err\",\"AWSAccountId\":\"$ACCOUNT_ID\",\"NewStateValue\":\"ALARM\",\"NewStateReason\":\"Error in Script\",\"StateChangeTime\":\"$TIMESTAMP\",\"Region\":\"$AWS_REGION\",\"OldStateValue\":\"OK\",\"Trigger\":{\"MetricName\":\"Deploy\",\"Dimensions\":[]}}"
  echo $msg
  local result=`aws sns publish --region=$AWS_REGION --topic-arn $topicARN --message "$msg"`
  echo $result
}

#fud=`grep fud /var/lib/cloud/instance/user-data.txt | awk '{ print $2 }' | tr -d 'fud='`

# Did set via userdata
if [ -f /home/ec2-user/deploy/magento.tar.gz ]; then
      aws s3 mv s3://current-magento-$fud/magento.tar.gz s3://archive-magento-$fud > /dev/null 2>&1

      counter=3
      #This loop will send notification to Cherwell if it is not through
      S3FROMLOCAL_DONE=0
      while [ $counter -gt 0 ]
      do
            aws s3 mv /home/ec2-user/deploy/magento.tar.gz s3://current-magento-$fud > /dev/null 2>&1
            RESULT=$?
            if [ $RESULT -eq 0 ]; then
                  S3FROMLOCAL_DONE=1
                  break
            else
                  sleep 30
                  counter=-1
            fi
      done


      if [[ $S3FROMLOCAL_DONE != 1 ]]; then
        sendErrorToSQS "/usr/local/bin/Deploy cannot copy /home/ec2-user/deploy/magento.tar.gz to s3://archive-magento-$fud.  Script timeout exceeded."
        exit 1
      fi

else
      # sendErrorToSQS "/home/ec2-user/deploy/magento.tar.gz not found"
      echo "/home/ec2-user/deploy/magento.tar.gz not found"
      exit 2
fi
EOF

# Set permissions
chmod 775 /usr/local/bin/Deploy
echo "*/15 * * * * /usr/local/bin/Deploy" > /var/spool/cron/ec2-user
chmod 600 /var/spool/cron/ec2-user
chown ec2-user:ec2-user /var/spool/cron/ec2-user
