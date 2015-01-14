#!/bin/bash

# Full system path to the directory containing this file, with trailing slash.
# This line determines the location of the script even when called from a bash
# prompt in another directory (in which case `pwd` will point to that directory
# instead of the one containing this script).  See http://stackoverflow.com/a/246128
mydir="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/"

# Source config file or exit.
if [ -e ${mydir}/config.sh ]; then
  source ${mydir}/config.sh
else
  echo "Could not find required config file at ${mydir}/config.sh. Exiting."
  exit 1
fi

# if [[ "${TARGET_VERSION}x" == "x" || "${SITEDIR}x" == "x" ]]; then
#   echo "Missing required settings in config.sh. Please edit the file and try again. Exiting."
#   exit 
# fi

# Include functions script.
if [[ -e ${mydir}/functions.sh ]]; then
  source ${mydir}/functions.sh
else 
  echo "Could not find required functions file at ${mydir}/functions.sh. Exiting."
  exit 1
fi


# Ensure sufficient arguments.
if [ "$#" != "3" ]; then
  echo "Usage: $0 basename drupal_version civicrm_version"
  echo "  basename: Used in a few ways:"
  echo "    directory under $mydir to use as document root;"
  echo "    used in the site URL as \${basename}.${basedomain};"
  echo "    used in the site Drupal and CiviCRM directories as"
  echo "    localhost_\${basename}_drupal and localhost_\${basename}_civicrm;"
  echo "  drupal_version: Drupal version to install"
  echo "  civicrm_version: CiviCRM version to install"
  exit 1
fi

basename=$1
drupal_version=$2
civicrm_version=$3

db_name_drupal="localhost_${basename}_drupal"
db_name_civicrm="localhost_${basename}_civicrm"

if command -v makevhost >/dev/null 2>&1; then
  if ! makevhost "${basename}.${basedomain}" "$root_directory/$basename"; then
    echo "ERROR: makevhost failed. Exiting."
    exit 1
  fi
fi

if [[ check_exists ]]; then
  echo "One or more of the following already exist:"
  echo "  Drupal database ${db_name_drupal}"
  echo "  CiviCRM database ${db_name_civicrm}"
  echo "  Base directory $root_directory/$basename"
  echo "Do you want to delete all of them and completely and reinstall? [Y/n]"
  read confirm_delete
  case $confirm_delete in
    [yY] | [yY][Ee][Ss] )
      echo "Deleting and re-installing."
      do_delete
      ;;
    [nN] | [nN][Oo] )
      echo "Exiting.";
      exit 1
      ;;
     *) echo "Invalid input. Please enter 'yes' or 'no'."
      exit 1
      ;;
  esac
fi

mysql --user=$mysql_root_user_name --password=$mysql_root_user_pass -e "
  CREATE DATABASE ${db_name_drupal};
  CREATE DATABASE ${db_name_civicrm};
  GRANT ALL PRIVILEGES ON ${db_name_drupal}.* TO
    ${mysql_site_user_name}@'localhost' IDENTIFIED BY '${mysql_site_user_pass}';
  GRANT ALL PRIVILEGES ON ${db_name_civicrm}.* TO
    ${mysql_site_user_name}@'localhost' IDENTIFIED BY '${mysql_site_user_pass}';
"

drush dl "drupal-${drupal_version}" -y --destination=$root_directory --drupal-project-rename=$basename
cd $root_directory/$basename
drush si -y --db-url="mysql://${mysql_site_user_name}:${mysql_site_user_pass}@localhost/${db_name_drupal}" --site-name="${basename}" --account-pass="admin"

drupal_major_version=$(print_drupal_version)

mkdir -p ${mydir}/downloads
extract_directory=$(mktemp -d $mydir/downloads/extract_XXX)

echo "Fetching source for ${civicrm_version}"
download_and_extract_tarball $civicrm_version $extract_directory

echo "Replacing CiviCRM with source for ${civicrm_version}"
mkdir -p $root_directory/$basename/sites/all/modules/.
mv $extract_directory/civicrm $root_directory/$basename/sites/all/modules/.
rm -rf $extract_directory

chmod a+w $root_directory/$basename/sites/default
chmod -R a+w $root_directory/$basename/sites/default/files

curl --data "database=MySQLDatabase&mysql[server]=localhost&mysql[username]=${mysql_site_user_name}&mysql[password]=${mysql_site_user_pass}&mysql[database]=${db_name_civicrm}&drupal[server]=localhost&drupal[username]=${mysql_site_user_name}&drupal[password]=${mysql_site_user_pass}&drupal[database]=${db_name_drupal}&loadGenerated=1&go=Check+Requirements+and+Install+CiviCRM" "http://${basename}.localhost/sites/all/modules/civicrm/install/index.php" | lynx -stdin

echo "Site URL: http://${basename}.localhost"