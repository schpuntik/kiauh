### base variables
SYSTEMDDIR="/etc/systemd/system"
OCTOPRINT_ENV="${HOME}/OctoPrint"

octoprint_setup_dialog(){
  status_msg "Initializing OctoPrint installation ..."

  ### count amount of klipper services
  if [ "$(systemctl list-units --full -all -t service --no-legend | grep -F "klipper.service")" ]; then
    INSTANCE_COUNT=1
  else
    INSTANCE_COUNT=$(systemctl list-units --full -all -t service --no-legend | grep -E "klipper-[[:digit:]].service" | wc -l)
  fi

  ### instance confirmation dialog
  while true; do
      echo
      top_border
      if [ $INSTANCE_COUNT -gt 1 ]; then
        printf "|%-55s|\n" " $INSTANCE_COUNT Klipper instances were found!"
      else
        echo -e "| 1 Klipper instance was found!                         | "
      fi
      echo -e "| You need one OctoPrint instance per Klipper instance. | "
      bottom_border
      echo
      read -p "${cyan}###### Create $INSTANCE_COUNT OctoPrint instances? (Y/n):${default} " yn
      case "$yn" in
        Y|y|Yes|yes|"")
          echo -e "###### > Yes"
          status_msg "Creating $INSTANCE_COUNT OctoPrint instances ..."
          octoprint_setup
          break;;
        N|n|No|no)
          echo -e "###### > No"
          warn_msg "Exiting OctoPrint setup ..."
          echo
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
    esac
  done
}

octoprint_dependencies(){
  dep=(
    git
    wget
    python-pip
    python-dev
    libyaml-dev
    build-essential
    python-setuptools
    python-virtualenv
    )
  dependency_check
}

octoprint_setup(){
  ### check and install all dependencies
  octoprint_dependencies

  ### add user to usergroups and add reboot permissions
  add_to_groups
  add_reboot_permission

  ### create and activate the virtualenv
  [ ! -d $OCTOPRINT_ENV ] && mkdir -p $OCTOPRINT_ENV
  status_msg "Set up virtualenv ..."
  cd $OCTOPRINT_ENV
  virtualenv venv
  source venv/bin/activate

  ### install octoprint with pip
  status_msg "Download and install OctoPrint ..."
  pip install pip --upgrade
  pip install --no-cache-dir octoprint
  ok_msg "Download complete!"

  ### leave virtualenv
  deactivate

  ### set up instances
  INSTANCE=1
  if [ $INSTANCE_COUNT -eq $INSTANCE ]; then
    create_single_octoprint_instance
  else
    create_multi_octoprint_instance
  fi
}

add_to_groups(){
  if [ ! "$(groups | grep tty)" ]; then
    status_msg "Adding user '${USER}' to group 'tty' ..."
    sudo usermod -a -G tty ${USER} && ok_msg "Done!"
  fi
  if [ ! "$(groups | grep dialout)" ]; then
    status_msg "Adding user '${USER}' to group 'dialout' ..."
    sudo usermod -a -G dialout ${USER} && ok_msg "Done!"
  fi
}

create_single_octoprint_startscript(){
### create single instance systemd service file
sudo /bin/sh -c "cat > ${SYSTEMDDIR}/octoprint.service" << OCTOPRINT
[Unit]
Description=Starts OctoPrint on startup
After=network-online.target
Wants=network-online.target

[Service]
Environment="LC_ALL=C.UTF-8"
Environment="LANG=C.UTF-8"
Type=simple
User=$USER
ExecStart=${OCTOPRINT_ENV}/venv/bin/octoprint --basedir ${BASEDIR} --config ${CONFIG_YAML} --port=${PORT} serve

[Install]
WantedBy=multi-user.target
OCTOPRINT
}

create_multi_octoprint_startscript(){
### create multi instance systemd service file
sudo /bin/sh -c "cat > ${SYSTEMDDIR}/octoprint-$INSTANCE.service" << OCTOPRINT
[Unit]
Description=Starts OctoPrint instance $INSTANCE on startup
After=network-online.target
Wants=network-online.target

[Service]
Environment="LC_ALL=C.UTF-8"
Environment="LANG=C.UTF-8"
Type=simple
User=$USER
ExecStart=${OCTOPRINT_ENV}/venv/bin/octoprint --basedir ${BASEDIR} --config ${CONFIG_YAML} --port=${PORT} serve

[Install]
WantedBy=multi-user.target
OCTOPRINT
}

create_config_yaml(){
### create multi instance config.yaml file
/bin/sh -c "cat > ${BASEDIR}/config.yaml" << CONFIGYAML
serial:
    additionalPorts:
    - ${TMP_PRINTER}
    disconnectOnErrors: false
    port: ${TMP_PRINTER}
server:
    commands:
        serverRestartCommand: ${RESTART_COMMAND}
        systemRestartCommand: sudo shutdown -r now
        systemShutdownCommand: sudo shutdown -h now
CONFIGYAML
}

create_single_octoprint_instance(){
  status_msg "Setting up 1 OctoPrint instance ..."

  ### single instance variables
  PORT=5000
  BASEDIR="${HOME}/.octoprint"
  TMP_PRINTER="/tmp/printer"
  CONFIG_YAML="$BASEDIR/config.yaml"
  RESTART_COMMAND="sudo service octoprint restart"

  ### declare empty array for ips which get displayed to the user at the end of the setup
  HOSTNAME=$(hostname -I | cut -d" " -f1)
  op_ip_list=()

  ### create instance
  status_msg "Creating single OctoPrint instance ..."
  create_single_octoprint_startscript
  op_ip_list+=("$HOSTNAME:$PORT")

  ### create the config.yaml
  if [ ! -f $BASEDIR/config.yaml ]; then
    status_msg "Creating config.yaml ..."
    [ ! -d $BASEDIR ] && mkdir $BASEDIR
    create_config_yaml
    ok_msg "Config created!"
  fi

  ### enable instance
  sudo systemctl enable octoprint.service
  ok_msg "Single OctoPrint instance created!"

  ### launching instance
  status_msg "Launching OctoPrint instance ..."
  sudo systemctl start octoprint

  ### confirm message
  CONFIRM_MSG="Single OctoPrint instance has been set up!"
  print_msg && clear_msg

  ### display all octoprint ips to the user
  print_op_ip_list; echo
}

create_multi_octoprint_instance(){
  status_msg "Setting up $INSTANCE_COUNT instances of OctoPrint ..."

  ### declare empty array for ips which get displayed to the user at the end of the setup
  HOSTNAME=$(hostname -I | cut -d" " -f1)
  op_ip_list=()

  ### default port
  PORT=5000

  while [ $INSTANCE -le $INSTANCE_COUNT ]; do
    ### multi instance variables
    BASEDIR="${HOME}/.octoprint-$INSTANCE"
    TMP_PRINTER="/tmp/printer-$INSTANCE"
    CONFIG_YAML="$BASEDIR/config.yaml"
    RESTART_COMMAND="sudo service octoprint restart"

    ### create instance
    status_msg "Creating instance #$INSTANCE ..."
    create_multi_octoprint_startscript
    op_ip_list+=("$HOSTNAME:$PORT")

    ### create the config.yaml
    if [ ! -f $BASEDIR/config.yaml ]; then
      status_msg "Creating config.yaml for instance #$INSTANCE..."
      [ ! -d $BASEDIR ] && mkdir $BASEDIR
      create_config_yaml
      ok_msg "Config #$INSTANCE created!"
    fi

    ### enable instance
    sudo systemctl enable octoprint-$INSTANCE.service
    ok_msg "OctoPrint instance $INSTANCE created!"

    ### launching instance
    status_msg "Launching OctoPrint instance $INSTANCE ..."
    sudo systemctl start octoprint-$INSTANCE

    ### instance counter +1
    INSTANCE=$(expr $INSTANCE + 1)

    ### port +1
    PORT=$(expr $PORT + 1)
  done

  ### confirm message
  CONFIRM_MSG="$INSTANCE_COUNT OctoPrint instances have been set up!"
  print_msg && clear_msg

  ### display all moonraker ips to the user
  print_op_ip_list; echo
}

add_reboot_permission(){
  USER=${USER}
  #create a backup when file already exists
  if [ -f /etc/sudoers.d/octoprint-shutdown ]; then
    sudo mv /etc/sudoers.d/octoprint-shutdown /etc/sudoers.d/octoprint-shutdown.old
  fi
  #create new permission file
  status_msg "Add reboot permission to user '$USER' ..."
  cd ${HOME} && echo "$USER ALL=NOPASSWD: /sbin/shutdown" > octoprint-shutdown
  sudo chown 0 octoprint-shutdown
  sudo mv octoprint-shutdown /etc/sudoers.d/octoprint-shutdown
  ok_msg "Permission set!"
}

print_op_ip_list(){
  i=1
  for ip in ${op_ip_list[@]}; do
    echo -e "       ${cyan}● Instance $i:${default} $ip"
    i=$((i + 1))
  done
}