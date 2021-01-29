install_moonraker(){
  python3_check
  if [ $py_chk_ok = "true" ]; then
    system_check_moonraker
    #ask user for customization
    get_user_selections_moonraker
    #disable/remove haproxy/lighttpd
    handle_haproxy_lighttpd
    #moonraker main installation
    moonraker_setup
    check_for_folder_moonraker
    #setup configs
    setup_printer_config_moonraker
    setup_moonraker_conf
    #execute customizations
    write_custom_trusted_clients
    symlinks_moonraker
    disable_octoprint
    #after install actions
    restart_moonraker
    restart_klipper
  else
    ERROR_MSG="Python 3.7 or above required!\n Please upgrade your Python version first."
    print_msg && clear_msg
  fi
}

python3_check(){
  status_msg "Your Python 3 version is: $(python3 --version)"
  major=$(python3 --version | cut -d" " -f2 | cut -d"." -f1)
  minor=$(python3 --version | cut -d"." -f2)
  if [ $major -ge 3 ] && [ $minor -ge 7 ]; then
    ok_msg "Python version ok!"
    py_chk_ok="true"
  else
    py_chk_ok="false"
  fi
}

system_check_moonraker(){
  status_msg "Initializing Moonraker installation ..."
  #check for existing printer.cfg and for the location
  locate_printer_cfg
  if [ -f $PRINTER_CFG ]; then
    PRINTER_CFG_FOUND="true"
    PRINTER_CFG_LOC=$PRINTER_CFG
  else
    PRINTER_CFG_FOUND="false"
  fi
  #check for existing klippy.log symlink in /klipper_config
  [ ! -e ${HOME}/klipper_config/klippy.log ] && KLIPPY_SL_FOUND="false"
  #check for existing moonraker.log symlink in /klipper_config
  [ ! -e ${HOME}/klipper_config/moonraker.log ] && MOONRAKER_SL_FOUND="false"
  #check for existing moonraker.conf
  if [ ! -f ${HOME}/moonraker.conf ]; then
    MOONRAKER_CONF_FOUND="false"
  else
    MOONRAKER_CONF_FOUND="true"
  fi
  #check if octoprint is installed
  if systemctl is-enabled octoprint.service -q 2>/dev/null; then
    unset OCTOPRINT_ENABLED
    OCTOPRINT_ENABLED="true"
  fi
  #check if haproxy is installed
  if [[ $(dpkg-query -f'${Status}' --show haproxy 2>/dev/null) = *\ installed ]]; then
    HAPROXY_FOUND="true"
  fi
  #check if lighttpd is installed
  if [[ $(dpkg-query -f'${Status}' --show lighttpd 2>/dev/null) = *\ installed ]]; then
    LIGHTTPD_FOUND="true"
  fi
}

get_user_selections_moonraker(){
  #user selection for printer.cfg
  if [ "$PRINTER_CFG_FOUND" = "false" ]; then
    while true; do
      echo
      top_border
      echo -e "|         ${red}WARNING! - No printer.cfg was found!${default}          |"
      hr
      echo -e "|  KIAUH can create a minimal printer.cfg with only the |"
      echo -e "|  recommended Moonraker config entries if you wish.    |"
      echo -e "|                                                       |"
      echo -e "|  Please be aware, that this option will ${red}NOT${default} create a  |"
      echo -e "|  fully working printer.cfg for you!                   |"
      bottom_border
      read -p "${cyan}###### Create a default printer.cfg? (Y/n):${default} " yn
      case "$yn" in
        Y|y|Yes|yes|"")
          echo -e "###### > Yes"
          SEL_DEF_CFG="true"
          break;;
        N|n|No|no)
          echo -e "###### > No"
          SEL_DEF_CFG="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  fi
  #user selection for moonraker.log symlink
  if [ "$KLIPPY_SL_FOUND" = "false" ]; then
    while true; do
      echo
      read -p "${cyan}###### Create klippy.log symlink? (y/N):${default} " yn
      case "$yn" in
        Y|y|Yes|yes)
          echo -e "###### > Yes"
          SEL_KLIPPYLOG_SL="true"
          break;;
        N|n|No|no|"")
          echo -e "###### > No"
          SEL_KLIPPYLOG_SL="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  fi
  #user selection for moonraker.log symlink
  if [ "$MOONRAKER_SL_FOUND" = "false" ]; then
    while true; do
      echo
      read -p "${cyan}###### Create moonraker.log symlink? (y/N):${default} " yn
      case "$yn" in
        Y|y|Yes|yes)
          echo -e "###### > Yes"
          SEL_MRLOG_SL="true"
          break;;
        N|n|No|no|"")
          echo -e "###### > No"
          SEL_MRLOG_SL="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  fi
  #ask user for more trusted clients
    while true; do
      echo
      top_border
      echo -e "| Apart from devices of your local network, you can add |"
      echo -e "| additional trusted clients to the moonraker.conf file |"
      bottom_border
      read -p "${cyan}###### Add additional trusted clients? (y/N):${default} " yn
      case "$yn" in
        Y|y|Yes|yes)
          echo -e "###### > Yes"
          ADD_TRUSTED_CLIENT="true"
          custom_trusted_clients
          break;;
        N|n|No|no|"")
          echo -e "###### > No"
          ADD_TRUSTED_CLIENT="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  #ask user to disable octoprint when such installed service was found
  if [ "$OCTOPRINT_ENABLED" = "true" ]; then
    unset DISABLE_OPRINT
    while true; do
      echo
      warn_msg "OctoPrint service found!"
      echo -e "You might consider disabling the OctoPrint service,"
      echo -e "since an active OctoPrint service may lead to unexpected"
      echo -e "behavior of the Mainsail Webinterface."
      read -p "${cyan}###### Do you want to disable OctoPrint now? (Y/n):${default} " yn
      case "$yn" in
        Y|y|Yes|yes|"")
          echo -e "###### > Yes"
          DISABLE_OPRINT="true"
          break;;
        N|n|No|no)
          echo -e "###### > No"
          DISABLE_OPRINT="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  fi
  #notify user about haproxy or lighttpd services found and possible issues
  if [ "$HAPROXY_FOUND" = "true" ] || [ "$LIGHTTPD_FOUND" = "true" ]; then
    while true; do
      echo
      top_border
      echo -e "| ${red}Possibly disruptive/incompatible services found!${default}      |"
      hr
      if [ "$HAPROXY_FOUND" = "true" ]; then
        echo -e "| ● haproxy                                             |"
      fi
      if [ "$LIGHTTPD_FOUND" = "true" ]; then
        echo -e "| ● lighttpd                                            |"
      fi
      hr
      echo -e "| Having those packages installed can lead to unwanted  |"
      echo -e "| behaviour. It is recommend to remove those packages.  |"
      echo -e "|                                                       |"
      echo -e "| 1) Remove packages (recommend)                        |"
      echo -e "| 2) Disable only (may cause issues)                    |"
      echo -e "| ${red}3) Skip this step (not recommended)${default}                   |"
      bottom_border
      read -p "${cyan}###### Please choose:${default} " action
      case "$action" in
        1)
          echo -e "###### > Remove packages"
          if [ "$HAPROXY_FOUND" = "true" ]; then
            DISABLE_HAPROXY="false"
            REMOVE_HAPROXY="true"
          fi
          if [ "$LIGHTTPD_FOUND" = "true" ]; then
            DISABLE_LIGHTTPD="false"
            REMOVE_LIGHTTPD="true"
          fi
          break;;
        2)
          echo -e "###### > Disable only"
          if [ "$HAPROXY_FOUND" = "true" ]; then
            DISABLE_HAPROXY="true"
            REMOVE_HAPROXY="false"
          fi
          if [ "$LIGHTTPD_FOUND" = "true" ]; then
            DISABLE_LIGHTTPD="true"
            REMOVE_LIGHTTPD="false"
          fi
          break;;
        3)
          echo -e "###### > Skip"
          DISABLE_LIGHTTPD="false"
          REMOVE_LIGHTTPD="false"
          DISABLE_HAPROXY="false"
          REMOVE_HAPROXY="false"
          break;;
        *)
          print_unkown_cmd
          print_msg && clear_msg;;
      esac
    done
  fi
  status_msg "Installation will start now! Please wait ..."
}

#############################################################
#############################################################

moonraker_setup(){
  dep=(wget curl unzip dfu-util libjpeg-dev zlib1g-dev)
  dependency_check
  status_msg "Downloading Moonraker ..."
  #force remove existing moonraker dir
  [ -d $MOONRAKER_DIR ] && rm -rf $MOONRAKER_DIR
  #clone into fresh moonraker dir
  cd ${HOME} && git clone $MOONRAKER_REPO
  ok_msg "Download complete!"
  status_msg "Installing Moonraker ..."
  $MOONRAKER_DIR/scripts/install-moonraker.sh
  #copy moonraker configuration for nginx to /etc/nginx/conf.d
  setup_moonraker_nginx_cfg
  #backup a possible existing printer.cfg at the old location and before patching in the new location
  backup_printer_cfg
  patch_klipper_sysfile "moonraker"
  #re-run printer.cfg location function to read the new path for the printer.cfg
  locate_printer_cfg
  echo; ok_msg "Moonraker successfully installed!"
}

patch_klipper_sysfile(){
  if [ -e $KLIPPER_SERVICE2 ]; then
    status_msg "Checking /etc/default/klipper for necessary entries ..."
    #patching new printer.cfg location to /etc/default/klipper
    if [ "$1" = "moonraker" ]; then
      if ! grep -q "/klipper_config/printer.cfg" $KLIPPER_SERVICE2; then
        status_msg "Patching new printer.cfg location to /etc/default/klipper ..."
        sudo sed -i "/KLIPPY_ARGS=/ s|$PRINTER_CFG|/home/${USER}/klipper_config/printer.cfg|" $KLIPPER_SERVICE2
        ok_msg "New location is: '/home/${USER}/klipper_config/printer.cfg'"
      fi
    fi
    #patching new UDS argument to /etc/default/klipper
    if [ "$1" = "moonraker" ] || [ "$1" = "dwc2" ]; then
      if ! grep -q -- "-a /tmp/klippy_uds" $KLIPPER_SERVICE2; then
        status_msg "Patching unix domain socket to /etc/default/klipper ..."
        #append the new argument to /tmp/klippy.log argument
        sudo sed -i "/KLIPPY_ARGS/s/\.log/\.log -a \/tmp\/klippy_uds/" $KLIPPER_SERVICE2
        ok_msg "Patching done!"
      fi
    fi
  fi
  if [ -e $KLIPPER_SERVICE3 ]; then
    status_msg "Checking /etc/systemd/system/klipper.service for necessary entries ..."
    #patching new printer.cfg location to /etc/systemd/system/klipper.service
    if [ "$1" = "moonraker" ]; then
      if ! grep -q "/klipper_config/printer.cfg" $KLIPPER_SERVICE3; then
        status_msg "Patching new printer.cfg location to /etc/systemd/system/klipper.service ..."
        sudo sed -i "/ExecStart=/ s|$PRINTER_CFG|/home/${USER}/klipper_config/printer.cfg|" $KLIPPER_SERVICE3
        ok_msg "New location is: '/home/${USER}/klipper_config/printer.cfg'"
        #set variable if file got edited
        SERVICE_FILE_PATCHED="true"
      fi
    fi
    #patching new UDS argument to /etc/systemd/system/klipper.service
    if [ "$1" = "moonraker" ] || [ "$1" = "dwc2" ]; then
      if ! grep -q -- "-a /tmp/klippy_uds" $KLIPPER_SERVICE3; then
        status_msg "Patching unix domain socket to /etc/systemd/system/klipper.service ..."
        #append the new argument to /tmp/klippy.log argument
        sudo sed -i "/ExecStart/s/\.log/\.log -a \/tmp\/klippy_uds/" $KLIPPER_SERVICE3
        ok_msg "Patching done!"
        #set variable if file got edited
        SERVICE_FILE_PATCHED="true"
      fi
    fi
    #reloading the units is only needed when the service file was patched.
    [ "$SERVICE_FILE_PATCHED" = "true" ] && status_msg "Reloading unit ..." && sudo systemctl daemon-reload
  fi
  ok_msg "Check complete!"
  echo
}

check_for_folder_moonraker(){
  #check for / create sdcard folder
  if [ ! -d ${HOME}/sdcard ]; then
    status_msg "Creating sdcard directory ..."
    mkdir ${HOME}/sdcard
    ok_msg "sdcard directory created!"
  fi
  ##check for / create klipper_config folder
  if [ ! -d ${HOME}/klipper_config ]; then
    status_msg "Creating klipper_config directory ..."
    mkdir ${HOME}/klipper_config
    ok_msg "klipper_config directory created!"
  fi
}

#############################################################
#############################################################

setup_printer_config_moonraker(){
  if [ "$PRINTER_CFG_FOUND" = "true" ]; then
    #copy printer.cfg to new location if there is no printer.cfg at the new location already
    if [ -f ${HOME}/printer.cfg ] && [ ! -f ${HOME}/klipper_config/printer.cfg ]; then
      status_msg "Copy printer.cfg to new location ..."
      cp ${HOME}/printer.cfg $PRINTER_CFG
      ok_msg "printer.cfg location: '$PRINTER_CFG'"
      ok_msg "Done!"
    fi
    #check printer.cfg for necessary moonraker entries
    read_printer_cfg "moonraker" && write_printer_cfg
  fi
  if [ "$SEL_DEF_CFG" = "true" ]; then
    status_msg "Creating minimal default printer.cfg ..."
    create_minimal_cfg
    ok_msg "printer.cfg location: '$PRINTER_CFG'"
    ok_msg "Done!"
  fi
}

setup_moonraker_conf(){
  if [ "$MOONRAKER_CONF_FOUND" = "false" ]; then
    status_msg "Creating moonraker.conf ..."
    cp ${HOME}/kiauh/resources/moonraker.conf ${HOME}
    ok_msg "moonraker.conf created!"
    status_msg "Writing trusted clients to config ..."
    write_default_trusted_clients
    ok_msg "Trusted clients written!"
  fi
  #check for at least one trusted client in an already existing moonraker.conf
  #if no entry is found, write default trusted client
  if [ "$MOONRAKER_CONF_FOUND" = "true" ]; then
    if grep "trusted_clients:" ${HOME}/moonraker.conf -q; then
      TC_LINE=$(grep -n "trusted_clients:" ${HOME}/moonraker.conf | cut -d ":" -f1)
      FIRST_IP_LINE=$(expr $TC_LINE + 1)
      FIRST_IP=$(sed -n "$FIRST_IP_LINE"p ${HOME}/moonraker.conf | cut -d" " -f5)
      #if [[ ! $FIRST_IP =~ ([0-9].[0-9].[0-9].[0-9]) ]]; then
      if [ "$FIRST_IP" = "" ]; then
        status_msg "Writing trusted clients to config ..."
        backup_moonraker_conf && write_default_trusted_clients
        ok_msg "Trusted clients written!"
      fi
    fi
  fi
}

setup_moonraker_nginx_cfg(){
  if [ ! -f $NGINX_CONFD/upstreams.conf ]; then
    sudo cp ${SRCDIR}/kiauh/resources/moonraker_nginx.cfg $NGINX_CONFD/upstreams.conf
  fi
  if [ ! -f $NGINX_CONFD/common_vars.conf ]; then
    sudo cp ${SRCDIR}/kiauh/resources/common_vars_nginx.cfg $NGINX_CONFD/common_vars.conf
  fi
}

#############################################################
#############################################################

write_default_trusted_clients(){
  DEFAULT_IP=$(hostname -I)
  status_msg "Your devices current IP adress is:\n${cyan}● $DEFAULT_IP ${default}"
  #make IP of the device KIAUH is exectuted on as
  #default trusted client and expand the IP range from 0 - 255
  DEFAULT_IP_RANGE="$(echo "$DEFAULT_IP" | cut -d"." -f1-3).0/24"
  status_msg "Writing the following IP range to moonraker.conf:\n${cyan}● $DEFAULT_IP_RANGE ${default}"
  #write the ip range in the first line below "trusted clients"
  #example: 192.168.1.0/24
  sed -i "/trusted_clients\:/a \ \ \ \ $DEFAULT_IP_RANGE" ${HOME}/moonraker.conf
  ok_msg "IP range of ● $DEFAULT_IP_RANGE written to moonraker.conf!"
}

#############################################################
#############################################################

custom_trusted_clients(){
  if [ "$ADD_TRUSTED_CLIENT" = "true" ]; then
    unset trusted_arr
    echo
    top_border
    echo -e "|  You can now add additional trusted clients to your   |"
    echo -e "|  moonraker.conf file. Be warned, that there is no     |"
    echo -e "|  spellcheck to check for valid input.                 |"
    echo -e "|  Make sure to type the IP correct!                    |"
    echo -e "|                                                       |"
    echo -e "|  If you want to add IP ranges, you can type in e.g.:  |"
    echo -e "|  192.168.1.0/24                                       |"
    echo -e "|  This will add the IPs 192.168.1.1 to 192.168.1.254   |"
    echo -e "|-------------------------------------------------------|"
    echo -e "|  You can add as many IPs / IP ranges as you want.     |"
    echo -e "|  When you are done type '${cyan}done${default}' to exit this dialoge.  |"
    bottom_border
    while true; do
      read -p "${cyan}###### Enter IP and press ENTER:${default} " TRUSTED_IP
      case "$TRUSTED_IP" in
        done)
          echo
          echo -e "List of IPs to add:"
          for ip in ${trusted_arr[@]}
          do
            echo -e "${cyan}● $ip ${default}"
          done
          while true; do
            echo
            echo -e "Select 'Yes' to confirm, 'No' to start again"
            echo -e "or 'Q' to abort and skip."
            read -p "${cyan}###### Confirm writing (Y/n/q):${default} " yn
            case "$yn" in
              Y|y|Yes|yes|"")
                echo -e "###### > Yes"
                TUSTED_CLIENT_CONFIRM="true"
                break;;
              N|n|No|no)
                echo -e "###### > No"
                custom_trusted_clients
                break;;
              Q|q)
                unset trusted_arr
                echo -e "###### > Abort"
                echo -e "${red}Aborting ...${default}"
                break;;
            esac
          done
          break;;
        *)
          trusted_arr+=($TRUSTED_IP);;
      esac
    done
  fi
}

write_custom_trusted_clients(){
  if [ "$TUSTED_CLIENT_CONFIRM" = "true" ]; then
    if [ "${#trusted_arr[@]}" != "0" ]; then
      for ip in ${trusted_arr[@]}
      do
        sed -i "/trusted_clients\:/a \ \ \ \ $ip" ${HOME}/moonraker.conf
      done
      ok_msg "Custom IPs written to moonraker.conf!"
    fi
  fi
}

symlinks_moonraker(){
  #create a klippy.log/moonraker.log symlink in klipper_config-dir just for convenience
  if [ "$SEL_KLIPPYLOG_SL" = "true" ] && [ ! -e ${HOME}/klipper_config/klippy.log ]; then
    status_msg "Creating klippy.log symlink ..."
    ln -s /tmp/klippy.log ${HOME}/klipper_config
    ok_msg "Symlink created!"
  fi
  if [ "$SEL_MRLOG_SL" = "true" ] && [ ! -e ${HOME}/klipper_config/moonraker.log ]; then
    status_msg "Creating moonraker.log symlink ..."
    ln -s /tmp/moonraker.log ${HOME}/klipper_config
    ok_msg "Symlink created!"
  fi
}

handle_haproxy_lighttpd(){
  #handle haproxy
  if [ "$DISABLE_HAPROXY" = "true" ]; then
    if systemctl is-active haproxy -q; then
      status_msg "Stopping haproxy service ..."
      sudo /etc/init.d/haproxy stop && ok_msg "Service stopped!"
    fi
    sudo systemctl disable haproxy
    ok_msg "Haproxy service disabled!"
  else
    if [ "$REMOVE_HAPROXY" = "true" ]; then
      if systemctl is-active haproxy -q; then
        status_msg "Stopping haproxy service ..."
        sudo /etc/init.d/haproxy stop && ok_msg "Service stopped!"
      fi
      status_msg "Removing haproxy ..."
      sudo apt-get remove haproxy -y
      sudo update-rc.d -f haproxy remove
      ok_msg "Haproxy removed!"
    fi
  fi
  #handle lighttpd
  if [ "$DISABLE_LIGHTTPD" = "true" ]; then
    if systemctl is-active lighttpd -q; then
      status_msg "Stopping lighttpd service ..."
      sudo /etc/init.d/lighttpd stop && ok_msg "Service stopped!"
    fi
    sudo systemctl disable lighttpd
    ok_msg "Lighttpd service disabled!"
  else
    if [ "$REMOVE_LIGHTTPD" = "true" ]; then
      if systemctl is-active lighttpd -q; then
        status_msg "Stopping lighttpd service ..."
        sudo /etc/init.d/lighttpd stop && ok_msg "Service stopped!"
      fi
      status_msg "Removing lighttpd ..."
      sudo apt-get remove lighttpd -y
      sudo update-rc.d -f lighttpd remove
      ok_msg "Lighttpd removed!"
    fi
  fi
}