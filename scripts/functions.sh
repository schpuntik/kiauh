# setting up some frequently used functions
check_euid(){
  if [ "$EUID" -eq 0 ]
  then
    echo -e "${red}"
    top_border
    echo -e "|       !!! THIS SCRIPT MUST NOT RAN AS ROOT !!!        |"
    bottom_border
    echo -e "${default}"
    exit 1
  fi
}

check_klipper_cfg_path(){
  source_kiauh_ini
  if [ -z $klipper_cfg_loc ]; then
    echo
    top_border
    echo -e "|                    ${red}!!! WARNING !!!${default}                    |"
    echo -e "|        ${red}No Klipper configuration directory set!${default}        |"
    hr
    echo -e "|  Before we can continue, KIAUH needs to know where    |"
    echo -e "|  you want your printer configuration to be.           |"
    blank_line
    echo -e "|  Please specify a folder where your Klipper configu-  |"
    echo -e "|  ration is stored or, if you don't have one yet, in   |"
    echo -e "|  which it should be saved after the installation.     |"
    bottom_border
    change_klipper_cfg_path
  fi
}

change_klipper_cfg_path(){
  source_kiauh_ini
  old_klipper_cfg_loc="$klipper_cfg_loc"
  EXAMPLE_FOLDER=$(printf "%s/your_config_folder" "${HOME}")
  while true; do
    top_border
    echo -e "|  ${red}IMPORTANT:${default}                                           |"
    echo -e "|  Please enter the new path in the following format:   |"
    printf "|  ${yellow}%-51s${default}  |\n" "$EXAMPLE_FOLDER"
    blank_line
    echo -e "|  By default 'klipper_config' is recommended!          |"
    bottom_border
    echo
    echo -e "${cyan}###### Please set the Klipper config directory:${default} "
    if [ -z "$old_klipper_cfg_loc" ]; then
      read -e -i "/home/${USER}/klipper_config" -e new_klipper_cfg_loc
    else
      read -e -i "$old_klipper_cfg_loc" -e new_klipper_cfg_loc
    fi
    echo
    read -p "${cyan}###### Set config directory to '${yellow}$new_klipper_cfg_loc${cyan}' ? (Y/n):${default} " yn
    case "$yn" in
      Y|y|Yes|yes|"")
        echo -e "###### > Yes"

        ### backup the old config dir
        backup_klipper_config_dir

        ### write new location to kiauh.ini
        sed -i "s|klipper_cfg_loc=$old_klipper_cfg_loc|klipper_cfg_loc=$new_klipper_cfg_loc|" $INI_FILE
        status_msg "Directory set to '$new_klipper_cfg_loc'!"

        ### write new location to klipper and moonraker service
        set_klipper_cfg_path
        echo; ok_msg "Config directory changed!"
        break;;
      N|n|No|no)
        echo -e "###### > No"
        change_klipper_cfg_path
        break;;
      *)
        print_unkown_cmd
        print_msg && clear_msg;;
    esac
  done
}

###? if path was changed in 'change_klipper_cfg_path', we need to edit the service files
###? and set the new path. after that, rename the old folder and reload service units.
###! users shouldn't try and move the files into subfolders with this function! as the mv command will fail
###! but the new path still gets written to the service files. if they really need to, they need to move all
###! config files or printer folder into that subfolder (still not recommended!)
set_klipper_cfg_path(){
  ### stop services
  klipper_service "stop" && moonraker_service "stop"

  ### rename the klipper config folder
  if [ ! -z "$old_klipper_cfg_loc" ] && [ -d "$old_klipper_cfg_loc" ]; then
    status_msg "Renaming '$old_klipper_cfg_loc' to '$new_klipper_cfg_loc'!"; echo
    mv -v "$old_klipper_cfg_loc" "$new_klipper_cfg_loc" && ok_msg "Done!"
  fi

  ### handle single klipper instance service file
  if [ -f /etc/systemd/system/klipper.service ]; then
    status_msg "Configuring Klipper for new path ..."
    sudo sed -i "/ExecStart=/ s|$old_klipper_cfg_loc/printer.cfg|$new_klipper_cfg_loc/printer.cfg|" /etc/systemd/system/klipper.service
    ok_msg "OK!"
  fi
  ### handle multi klipper instance service file
  if ls /etc/systemd/system/klipper-*.service 2>/dev/null 1>&2; then
    status_msg "Configuring Klipper for new path ..."
    for service in $(find /etc/systemd/system/klipper-*.service); do
      sudo sed -i "/ExecStart=/ s|$old_klipper_cfg_loc/printer_|$new_klipper_cfg_loc/printer_|" $service
    done
    ok_msg "OK!"
  fi

  ### handle single moonraker instance service and moonraker.conf file
  if [ -f /etc/systemd/system/moonraker.service ]; then
    status_msg "Configuring Moonraker for new path ..."
    sudo sed -i "/ExecStart=/ s|$old_klipper_cfg_loc/moonraker.conf|$new_klipper_cfg_loc/moonraker.conf|" /etc/systemd/system/moonraker.service
    ### replace old file path with new one in moonraker.conf
    sed -i "/config_path:/ s|config_path:.*|config_path: $new_klipper_cfg_loc|" $new_klipper_cfg_loc/moonraker.conf
    ok_msg "OK!"
  fi
  ### handle multi moonraker instance service file
  if ls /etc/systemd/system/moonraker-*.service 2>/dev/null 1>&2; then
    status_msg "Configuring Moonraker for new path ..."
    for service in $(find /etc/systemd/system/moonraker-*.service); do
      sudo sed -i "/ExecStart=/ s|$old_klipper_cfg_loc/printer_|$new_klipper_cfg_loc/printer_|" $service
    done
    ### replace old file path with new one in moonraker.conf
    for moonraker_conf in $(find $new_klipper_cfg_loc/printer_*/moonraker.conf); do
      loc=$(echo "$moonraker_conf" | rev | cut -d"/" -f2- | rev)
      sed -i "/config_path:/ s|config_path:.*|config_path: $loc|" $moonraker_conf
    done
    ok_msg "OK!"
  fi

  ### reloading units
  sudo systemctl daemon-reload

  ### restart services
  klipper_service "restart" && moonraker_service "restart"
}

source_kiauh_ini(){
  source $INI_FILE
}

klipper_service(){
  ### set a variable for the ok and status messages
  [ "$1" == "start" ] && ACTION1="started" && ACTION2="Starting"
  [ "$1" == "stop" ] && ACTION1="stopped" && ACTION2="Stopping"
  [ "$1" == "restart" ] && ACTION1="restarted" && ACTION2="Restarting"

  if ls /etc/systemd/system/klipper-*.service 2>/dev/null 1>&2; then
    INSTANCE_COUNT=$(systemctl list-units --full -all -t service --no-legend | grep -E "klipper-[[:digit:]].service" | wc -l)
    INSTANCE=1
    status_msg "$ACTION2 $INSTANCE_COUNT Klipper Services ..."
    while [ $INSTANCE -le $INSTANCE_COUNT ]; do
      sudo systemctl $1 klipper-$INSTANCE && ok_msg "Klipper Service #$INSTANCE $ACTION1!"
      ### instance counter +1
      INSTANCE=$(expr $INSTANCE + 1)
    done
  elif [ "$(systemctl list-units --full -all -t service --no-legend | grep -E "klipper.service")" ]; then
    status_msg "$ACTION2 Klipper Service ..."
    sudo systemctl $1 klipper && ok_msg "Klipper Service $ACTION1!"
  fi
}

moonraker_service(){
  ### set a variable for the ok and status messages
  [ "$1" == "start" ] && ACTION1="started" && ACTION2="Starting"
  [ "$1" == "stop" ] && ACTION1="stopped" && ACTION2="Stopping"
  [ "$1" == "restart" ] && ACTION1="restarted" && ACTION2="Restarting"

  if ls /etc/systemd/system/moonraker-*.service 2>/dev/null 1>&2; then
    INSTANCE_COUNT=$(systemctl list-units --full -all -t service --no-legend | grep -E "moonraker-[[:digit:]].service" | wc -l)
    INSTANCE=1
    status_msg "$ACTION2 $INSTANCE_COUNT Moonraker Services ..."
    while [ $INSTANCE -le $INSTANCE_COUNT ]; do
      sudo systemctl $1 moonraker-$INSTANCE && ok_msg "Moonraker Service #$INSTANCE $ACTION1!"
      ### instance counter +1
      INSTANCE=$(expr $INSTANCE + 1)
    done
  elif [ "$(systemctl list-units --full -all -t service --no-legend | grep -E "moonraker.service")" ]; then
    status_msg "$ACTION2 Moonraker Service ..."
    sudo systemctl $1 moonraker && ok_msg "Moonraker Service $ACTION1!"
  fi
}

dwc_service(){
  ### set a variable for the ok and status messages
  [ "$1" == "start" ] && ACTION1="started" && ACTION2="Starting"
  [ "$1" == "stop" ] && ACTION1="stopped" && ACTION2="Stopping"
  [ "$1" == "restart" ] && ACTION1="restarted" && ACTION2="Restarting"

  if ls /etc/systemd/system/dwc-*.service 2>/dev/null 1>&2; then
    INSTANCE_COUNT=$(systemctl list-units --full -all -t service --no-legend | grep -E "dwc-[[:digit:]].service" | wc -l)
    INSTANCE=1
    status_msg "$ACTION2 $INSTANCE_COUNT DWC-for-Klipper-Socket Services ..."
    while [ $INSTANCE -le $INSTANCE_COUNT ]; do
      sudo systemctl $1 dwc-$INSTANCE && ok_msg "DWC-for-Klipper-Socket Service #$INSTANCE $ACTION1!"
      ### instance counter +1
      INSTANCE=$(expr $INSTANCE + 1)
    done
  elif [ "$(systemctl list-units --full -all -t service --no-legend | grep -E "dwc.service")" ]; then
    status_msg "$ACTION2 DWC-for-Klipper-Socket Service ..."
    sudo systemctl $1 dwc && ok_msg "DWC-for-Klipper-Socket Service $ACTION1!"
  fi
}

octoprint_service(){
  ### set a variable for the ok and status messages
  [ "$1" == "start" ] && ACTION1="started" && ACTION2="Starting"
  [ "$1" == "stop" ] && ACTION1="stopped" && ACTION2="Stopping"
  [ "$1" == "restart" ] && ACTION1="restarted" && ACTION2="Restarting"
  [ "$1" == "enable" ] && ACTION1="enabled" && ACTION2="Enabling"
  [ "$1" == "disable" ] && ACTION1="disabled" && ACTION2="Disabling"

  if ls /etc/systemd/system/octoprint-*.service 2>/dev/null 1>&2; then
    INSTANCE=1
    INSTANCE_COUNT=$(systemctl list-unit-files | grep -E "octoprint.*" | wc -l)
    status_msg "$ACTION2 $INSTANCE_COUNT OctoPrint Services ..."
    while [ $INSTANCE -le $INSTANCE_COUNT ]; do
      sudo systemctl $1 octoprint-$INSTANCE && ok_msg "OctoPrint Service #$INSTANCE $ACTION1!"
      ### instance counter +1
      INSTANCE=$(expr $INSTANCE + 1)
    done
  elif [ "$(systemctl list-unit-files | grep -E "octoprint.*")" ]; then
    status_msg "$ACTION2 OctoPrint Service ..."
    sudo systemctl $1 octoprint && ok_msg "OctoPrint Service $ACTION1!"
  fi
}

toggle_octoprint_service(){
  if systemctl list-unit-files | grep -E "octoprint.*" | grep "enabled" &>/dev/null; then
    octoprint_service "stop"
    octoprint_service "disable"
    sleep 2
    CONFIRM_MSG=" OctoPrint Service is now >>> DISABLED <<< !"
  elif systemctl list-unit-files | grep -E "octoprint.*" | grep "disabled" &>/dev/null; then
    octoprint_service "enable"
    octoprint_service "start"
    sleep 2
    CONFIRM_MSG=" OctoPrint Service is now >>> ENABLED <<< !"
  else
    ERROR_MSG=" You cannot activate a service that does not exist!"
  fi
}

read_octoprint_service_status(){
  unset OPRINT_SERVICE_STATUS
  if systemctl list-unit-files | grep -E "octoprint*" | grep "enabled" &>/dev/null; then
    OPRINT_SERVICE_STATUS="${red}[Disable]${default} OctoPrint Service                       "
  else
    OPRINT_SERVICE_STATUS="${green}[Enable]${default} OctoPrint Service                        "
  fi
}

start_klipperscreen(){
  status_msg "Starting KlipperScreen Service ..."
  sudo systemctl start KlipperScreen && ok_msg "KlipperScreen Service started!"
}

stop_klipperscreen(){
  status_msg "Stopping KlipperScreen Service ..."
  sudo systemctl stop KlipperScreen && ok_msg "KlipperScreen Service stopped!"
}

restart_klipperscreen(){
  status_msg "Restarting KlipperScreen Service ..."
  sudo systemctl restart KlipperScreen && ok_msg "KlipperScreen Service restarted!"
}

restart_nginx(){
  if [ "$(systemctl list-units --full -all -t service --no-legend | grep -F "nginx.service")" ]; then
    status_msg "Restarting NGINX Service ..."
    sudo systemctl restart nginx && ok_msg "NGINX Service restarted!"
  fi
}

dependency_check(){
  status_msg "Checking for the following dependencies:"
  #check if package is installed, if not write name into array
  for pkg in "${dep[@]}"
  do
    echo -e "${cyan}● $pkg ${default}"
    if [[ ! $(dpkg-query -f'${Status}' --show $pkg 2>/dev/null) = *\ installed ]]; then
      inst+=($pkg)
    fi
  done
  #if array is not empty, install packages from array elements
  if [ "${#inst[@]}" != "0" ]; then
    status_msg "Installing the following dependencies:"
    for element in ${inst[@]}
    do
      echo -e "${cyan}● $element ${default}"
    done
    echo
    sudo apt-get install ${inst[@]} -y
    ok_msg "Dependencies installed!"
    #clearing the array
    unset inst
  else
    ok_msg "Dependencies already met! Continue..."
  fi
}

print_error(){
  for data in "${data_arr[@]}"
  do
    if [ ! -e $data ]; then
      data_count+=(0)
    else
      data_count+=(1)
    fi
  done
  sum=$(IFS=+; echo "$((${data_count[*]}))")
  if [ $sum -eq 0 ]; then
    ERROR_MSG="Looks like $1 was already removed!\n Skipping..."
  else
    ERROR_MSG=""
  fi
}

setup_gcode_shell_command(){
  echo
  top_border
  echo -e "| You are about to install the G-Code Shell Command     |"
  echo -e "| extension. Please make sure to read the instructions  |"
  echo -e "| before you continue and remember that potential risks |"
  echo -e "| can be involved after installing this extension!      |"
  blank_line
  echo -e "| ${red}You accept that you are doing this on your own risk!${default}  |"
  bottom_border
  while true; do
    read -p "${cyan}###### Do you want to continue? (Y/n):${default} " yn
    case "$yn" in
      Y|y|Yes|yes|"")
        if [ -d $KLIPPER_DIR/klippy/extras ]; then
          status_msg "Installing gcode shell command extension ..."
          status_msg "Copy gcode_shell_command.py to '$KLIPPER_DIR/klippy/extras' ..."
          if [ -f $KLIPPER_DIR/klippy/extras/gcode_shell_command.py ]; then
            warn_msg "There is already a file named 'gcode_shell_command.py'"
            warn_msg "in the destination location!"
            while true; do
              read -p "${cyan}###### Do you want to overwrite it? (Y/n):${default} " yn
              case "$yn" in
                Y|y|Yes|yes|"")
                  rm -f $KLIPPER_DIR/klippy/extras/gcode_shell_command.py
                  install_gcode_shell_command
                  break;;
                N|n|No|no)
                  break;;
              esac
            done
          else
            install_gcode_shell_command
          fi
        else
          ERROR_MSG="Folder ~/klipper/klippy/extras not found!"
        fi
        break;;
      N|n|No|no)
        break;;
      *)
        print_unkown_cmd
        print_msg && clear_msg;;
    esac
  done
}

install_gcode_shell_command(){
  klipper_service "stop"
  status_msg "Copy 'gcode_shell_command.py' to $KLIPPER_DIR/klippy/extras"
  cp ${SRCDIR}/kiauh/resources/gcode_shell_command.py $KLIPPER_DIR/klippy/extras
  echo
  while true; do
    read -p "${cyan}###### Do you want to create the example shell command? (Y/n):${default} " yn
    case "$yn" in
      Y|y|Yes|yes|"")
        status_msg "Copy shell_command.cfg ..."
        ### create a backup of the config folder
        backup_klipper_config_dir

        ### handle single printer.cfg
        if [ -f $klipper_cfg_loc/printer.cfg ] && [ ! -f $klipper_cfg_loc/shell_command.cfg ]; then
          ### copy shell_command.cfg to config location
          cp ${SRCDIR}/kiauh/resources/shell_command.cfg $klipper_cfg_loc
          ok_msg "$klipper_cfg_loc/shell_command.cfg created!"

          ### write the include to the very first line of the printer.cfg
          sed -i "1 i [include shell_command.cfg]" $klipper_cfg_loc/printer.cfg
        fi

        ### handle multi printer.cfg
        if ls $klipper_cfg_loc/printer_*  2>/dev/null 1>&2; then
          for config in $(find $klipper_cfg_loc/printer_*/printer.cfg); do
            path=$(echo $config | rev | cut -d"/" -f2- | rev)
            if [ ! -f $path/shell_command.cfg ]; then
              ### copy shell_command.cfg to config location
              cp ${SRCDIR}/kiauh/resources/shell_command.cfg $path
              ok_msg "$path/shell_command.cfg created!"

              ### write the include to the very first line of the printer.cfg
              sed -i "1 i [include shell_command.cfg]" $path/printer.cfg
            fi
          done
        fi
        break;;
      N|n|No|no)
        break;;
    esac
  done
  ok_msg "Shell command extension installed!"
  klipper_service "restart"
}

create_minimal_cfg(){
  #create a minimal default config
  if [ "$SEL_DEF_CFG" = "true" ]; then
		cat <<- EOF >> $PRINTER_CFG
		[mcu]
		serial: </dev/serial/by-id/your-mcu>

		[printer]
		kinematics: none
		max_velocity: 1
		max_accel: 1

		[virtual_sdcard]
		path: ~/sdcard

		[pause_resume]
		[display_status]
EOF
  fi
}

read_printer_cfg(){
  KIAUH_CFG="$(dirname $PRINTER_CFG)/kiauh.cfg"
  [ ! -f $KIAUH_CFG ] && KIAUH_CFG_FOUND="false" || KIAUH_CFG_FOUND="true"
  if [ -f $PRINTER_CFG ]; then
    if [ "$1" = "moonraker" ]; then
      [ ! "$(grep '^\[virtual_sdcard\]$' $PRINTER_CFG)" ] && VSD="false" && EDIT_CFG="true"
      [ ! "$(grep '^\[pause_resume\]$' $PRINTER_CFG)" ] && PAUSE_RESUME="false" && EDIT_CFG="true"
      [ ! "$(grep '^\[display_status\]$' $PRINTER_CFG)" ] && DISPLAY_STATUS="false" && EDIT_CFG="true"
    elif [ "$1" = "mainsail" ] || [ "$1" = "fluidd" ]; then
      [ ! "$(grep '^\[include webui_macros\.cfg\]$' $PRINTER_CFG)" ] && WEBUI_MACROS="false" && EDIT_CFG="true"
    elif [ "$1" = "dwc2" ]; then
      [ ! "$(grep '^\[virtual_sdcard\]$' $PRINTER_CFG)" ] && VSD="false" && EDIT_CFG="true"
    fi
  fi
}

write_printer_cfg(){
  #backup printer.cfg if edits will be written
  [ "$EDIT_CFG" = "true" ] && backup_printer_cfg
  #create kiauh.cfg if its needed and doesn't exist
  if [ "$KIAUH_CFG_FOUND" = "false" ] && [ "$EDIT_CFG" = "true" ]; then
    status_msg "Creating kiauh.cfg ..."
    echo -e "##### AUTOCREATED BY KIAUH #####" > $KIAUH_CFG
  fi
  #write each entry to kiauh.cfg if it doesn't exist
  #Moonraker/DWC2 related config options
  if [ "$VSD" = "false" ] && [[ ! $(grep '^\[virtual_sdcard\]$' $KIAUH_CFG) ]]; then
    echo -e "\n[virtual_sdcard]\npath: ~/sdcard" >> $KIAUH_CFG
  fi
  if [ "$PAUSE_RESUME" = "false" ] && [[ ! $(grep '^\[pause_resume]$' $KIAUH_CFG) ]]; then
    echo -e "\n[pause_resume]" >> $KIAUH_CFG
  fi
  if [ "$DISPLAY_STATUS" = "false" ] && [[ ! $(grep '^\[display_status]$' $KIAUH_CFG) ]]; then
    echo -e "\n[display_status]" >> $KIAUH_CFG
  fi
  #including the kiauh.cfg into printer.cfg if not already done
  if [ ! "$(grep '^\[include kiauh\.cfg\]$' $PRINTER_CFG)" ] && [ "$EDIT_CFG" = "true" ]; then
    status_msg "Writing [include kiauh.cfg] to printer.cfg ..."
    sed -i '1 i ##### AUTOCREATED BY KIAUH #####\n[include kiauh.cfg]' $PRINTER_CFG
  fi
  ok_msg "Done!"
}

init_ini(){
  ### copy an existing kiauh.ini to its new location to keep all possible saved values
  if [ -f ${SRCDIR}/kiauh/kiauh.ini ] && [ ! -f $INI_FILE ]; then
    cp ${SRCDIR}/kiauh/kiauh.ini $INI_FILE
  fi
  if [ ! -f $INI_FILE ]; then
    echo -e "#don't edit this file if you don't know what you are doing...\c" > $INI_FILE
  fi
  if [ ! $(grep -E "^backup_before_update=." $INI_FILE) ]; then
    echo -e "\nbackup_before_update=false\c" >> $INI_FILE
  fi
  if [ ! $(grep -E "^previous_origin_state=[[:alnum:]]" $INI_FILE) ]; then
    echo -e "\nprevious_origin_state=0\c" >> $INI_FILE
  fi
  if [ ! $(grep -E "^previous_smoothing_state=[[:alnum:]]" $INI_FILE) ]; then
    echo -e "\nprevious_smoothing_state=0\c" >> $INI_FILE
  fi
  if [ ! $(grep -E "^previous_shaping_state=[[:alnum:]]" $INI_FILE) ]; then
    echo -e "\nprevious_shaping_state=0\c" >> $INI_FILE
  fi
  if [ ! $(grep -E "^logupload_accepted=." $INI_FILE) ]; then
    echo -e "\nlogupload_accepted=false\c" >> $INI_FILE
  fi
  ###add empty klipper config path if missing
  if [ ! $(grep -E "^klipper_cfg_loc=" $INI_FILE) ]; then
    echo -e "\nklipper_cfg_loc=\c" >> $INI_FILE
  fi
}
