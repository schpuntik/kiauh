#ui total width = 57 chars
top_border(){
  echo -e "/=======================================================\ "
}

bottom_border(){
  echo -e "\=======================================================/"
}

blank_line(){
  echo -e "|                                                       | "
}

hr(){
  echo -e "|-------------------------------------------------------|"
}

quit_footer(){
  hr
  echo -e "|                        ${red}Q) Quit${default}                        | "
  bottom_border
}

print_header(){
  top_border
  echo -e "|     $(title_msg "~~~~~~~~~~~~~~~~~ [ KIAUH ] ~~~~~~~~~~~~~~~~~")     |"
  echo -e "|     $(title_msg "   Klipper Installation And Update Helper    ")     |"
  echo -e "|     $(title_msg "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")     |"
  bottom_border
}

kiauh_update_msg(){
  top_border
  echo -e "|  ${yellow}There is a newer version of this script available!${default}   | "
  echo -e "|  ${yellow}Type 'update' if you want to update KIAUH now.${default}       | "
  blank_line
  echo -e "|  ${yellow}Check out the KIAUH changelog for important changes${default}  | "
  echo -e "|  ${yellow}either to the script or the installable components!${default}  | "
  bottom_border
}

##############################################################################################
#********************************************************************************************#
##############################################################################################
### TODO: rework other menus to make use of the following functions too and make them more readable

do_action(){
  clear && print_header
  ### $1 is the action the user wants to fire
  $1
  print_msg && clear_msg
  ### $2 is the menu the user usually gets directed back to after an action is completed
  $2
}

deny_action(){
  clear && print_header
  print_unkown_cmd
  print_msg && clear_msg
  $1
}