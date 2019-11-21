#!/bin/bash
A=$(tput sgr0)
export TERM=xterm
echo ""
echo ""
echo -e '\E[33m'"----------------------------------- $A"
echo -e '\E[33m'"|   optional docker variable      | $A"
echo -e '\E[33m'"----------------------------------- $A"
echo -e '\E[33m'"----------------------------------- $A"
echo -e '\E[33m'"|    1)  LOCAL_MONITOR            | $A"
echo -e '\E[33m'"----------------------------------- $A"
echo ""
echo -e '\E[32m'"###################################### $A"
echo -e '\E[32m'"###          LOCAL_MONITOR         ### $A"
echo -e '\E[32m'"###################################### $A"
echo -e '\E[33m'"If you want the nagios server to monitor its own host (the container itself [localhost portion in ui]), use this environment variable, value should be 'Y' $A"
echo -e '\E[33m'"If you don't want to monitor the the container itself, Do not use this Environment variable $A"
echo ""
echo -e '\E[33m'"If you don't want localhost monitoring, It will shows some error because of the empty host-list, $A"
echo -e '\E[33m'"you can add new '<<name>>.cfg' file which have hosts and services under '/usr/local/nagios/etc/servers' and reload the service 'service nagios reload' or mount the location to the docker machine with the cfg file $A"
echo ""
echo "Configuring........"
sleep 5




# ##########################################
# function K8s_Login() {
#     if [[ ! -z "$K8S_CLUSTER_NAME" ]] && [[ ! -z "$K8S_CLUSTER_REGION" ]] ; then
#         su - nagios -c "aws eks update-kubeconfig --name $K8S_CLUSTER_NAME --region $K8S_CLUSTER_REGION"
#     else
#         echo "Expecting K8S_CLUSTER_NAME & K8S_CLUSTER_REGION for configuring kubectl"
#     fi
# }



##########################################
function Service_Config() {
#     K8s_Login
    echo "configuring nagios"
    if [[ ! -f /usr/local/nagios/etc/htpasswd.users ]] ; then
          if [[ "$DeploymentTime" = "" ]] ; then
               echo ""
               echo "ADMIN_USERNAME : NagiosAdmin"
               echo "ADMIN_PASSWORD : The password you are providing with 'DeploymentTime' environment variable"
               echo ""
               exit 0
          else
               sleep 1
          fi

          if [[ ! "$DeploymentTime" = "" ]] ; then
               export DeploymentTime=$(date +%F--%H-%M-%S--%Z)
          fi

          ADMIN_PASSWORD=$(base64 <<< $DeploymentTime)
          htpasswd -b -c /usr/local/nagios/etc/htpasswd.users NagiosAdmin $ADMIN_PASSWORD
          unset ADMIN_PASSWORD

cat <<EOF > /usr/local/bin/AdminPass
#!/bin/bash
base64 <<< \$DeploymentTime
EOF
          chmod a+x /usr/local/bin/AdminPass

          if [[ ! "$USER_PASSWORD" = "" ]] ; then
               htpasswd -b /usr/local/nagios/etc/htpasswd.users NagiosUser $USER_PASSWORD
               echo "authorized_for_read_only=NagiosUser" >> /usr/local/nagios/etc/cgi.cfg
          fi
    fi

    if [[ $LOCAL_MONITOR == "y" || $LOCAL_MONITOR == "Y" ]] ; then
        echo "not going to monitor the localhost"
    else
        sed -i "s|cfg_file=/usr/local/nagios/etc/objects/localhost.cfg|#cfg_file=/usr/local/nagios/etc/objects/localhost.cfg|g" /usr/local/nagios/etc/nagios.cfg
    fi

    if [[ ! -z $SMTP_SERVER ]] && [[ ! -z $SMTP_PORT ]] && [[ ! -z $SMTP_USERNAME ]] && [[ ! -z $SMTP_PASSWORD ]] ; then
        echo "SMTP Server Details available.....  Configuing SMTP Relay"
        postconf -e "relayhost = [$SMTP_SERVER]:$SMTP_PORT" \
            "smtp_sasl_auth_enable = yes" \
            "smtp_sasl_security_options = noanonymous" \
            "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" \
            "smtp_use_tls = yes" \
            "smtp_tls_security_level = encrypt" \
            "smtp_tls_note_starttls_offer = yes" \
            "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
        echo "[$SMTP_SERVER]:$SMTP_PORT $SMTP_USERNAME:$SMTP_PASSWORD" > /etc/postfix/sasl_passwd
        postmap /etc/postfix/sasl_passwd

        chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
        chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
    fi

    if [[ -z $NAGIOS_MAIL_SENDER ]] ; then
        NAGIOS_MAIL_SENDER=nagios.local
    fi
    
    sed -i "s|NAGIOS_MAIL_SENDER|$NAGIOS_MAIL_SENDER|g" /usr/local/nagios/etc/objects/commands.cfg
    postconf -e myhostname="`hostname -f`"
    postconf -e mydestination="`hostname -f`, localhost.localdomain, localhost"
    echo "`hostname -f`" > /etc/mailname
    sed -i "s|^result_limit=.*|result_limit=0|g" /usr/local/nagios/etc/cgi.cfg

    ln -s /etc/apache2/sites-available/nagios.conf /etc/apache2/sites-enabled/
    chown -R nagios:nagios /usr/local/nagios/etc/servers
}


##########################################
function Service_Start() {
    Service_Config
    a2enmod rewrite
    a2enmod cgi
    service xinetd restart & wait
    service nagios restart & wait
    # service apache2 restart & wait
    service postfix restart & wait
    apachectl -D FOREGROUND
}



Service_Start