#!/usr/bin/env zsh -f

#
# Rsync Deploy
# http://github.com/chauncey-garrett/rsync-deploy/
#
# A server deploy script designed to quickly deploy a site with release
# versions while simultaneously limiting downtime due to rollbacks, failed
# deploys, and simultaneous deploys.
#
# By Chauncey Garrett
# http://chauncey.io
# @chauncey_io
#

__ScriptVersion="0.1"

# Return if requirements are not found.
if (( ! $+commands[rsync] ))
then
	return 1
fi

#
# Environment variables for _deploy.zsh
#   These should be imported via a `.rsync-deploy-rc` file placed in the
#   root of the deploy path
#

# Get variables
config_file="${PWD}/.rsync-deploy-rc"
[[ -f ${config_file} ]] && source "${config_file}"

#
# ssh_cmd
#

ssh_cmd()
{
	ssh -p "${port}" -i "${ssh_key}" "${username}"@"${hostname}" -T ${@}
}

#
# Assign server variables
#

get-server-variables() {

	# Determine the current release version
	num_version_last="$(ssh_cmd cat ${path_deploy_to}/last_version)" || exit 30
	(( num_version_current = num_version_last+1 ))

	# Determine the number of releases
	num_releases="$( ssh_cmd "ls -1d ${path_deploy_to}/${dir_deploy_releases}/[0-9]* | sort -rn | wc -l" )" || exit 35
	num_releases_remove=$(( ${num_releases} > ${keep_releases} ? ${num_releases} - ${keep_releases} : 0 ))
}

#
# ssh_cmd_init_test
#   Ensure deploy path doesn't already exist
#

ssh_cmd_init_test() {
	test="$( ssh_cmd find ${path_deploy_to} -maxdepth 0 -empty )"
	[[ ! "${test}" = '' ]] ||
( echo "
! ERROR: Deploy path already exists.
!
! You may need to set up manually. See rsync-deploy.zsh help:
!
      rsync-deploy.zsh --help
!
! OR start over with:
!
      rm -rf ${path_deploy_to}
!" && exit 50 )
}

#
# ssh_cmd_init
#

ssh_cmd_init()
{
cat << EOF
echo "-----> Setting up ${path_deploy_to}\n" &&
(
	mkdir -p "${path_deploy_to}" &&
		chown -R "$(whoami)" "${path_deploy_to}" &&
		chmod g+rx,u+rwx "${path_deploy_to}" &&
		mkdir -p "${path_deploy_to}/${dir_deploy_releases}" &&
		chmod g+rx,u+rwx "${path_deploy_to}/${dir_deploy_releases}" &&
		mkdir -p "${path_deploy_to}/${dir_deploy_cache}" &&
		chmod g+rx,u+rwx "${path_deploy_to}/${dir_deploy_cache}" &&
		echo "0" >! "${path_deploy_to}/last_version" &&
		ls -la "${path_deploy_to}" &&
		echo "\n-----> Done."
) || (
cat <<- EOT
! ERROR: Setup failed.
!
! Ensure that the path ${path_deploy_to} is accessible to the SSH user.
! You may need to run:
!
      sudo mkdir -p ${path_deploy_to} && sudo chown -R ${username} ${path_deploy_to}
!
EOT
)
EOF
}

#
# deploy-rsync-cache
#   Create and update a cache file for faster builds
#

deploy-rsync-cache()
{
	# Lock
	ssh_cmd_lock | ssh_cmd
	local exit_code=$?
	[[ ${exit_code} != 0 ]] && exit ${exit_code}

	echo "-----> Updating cache @ ${username}@${hostname}:${path_deploy_to}/${dir_deploy_cache}\n"

	# Base rsync options
	local rsync_options
	rsync_options=( --verbose --progress --human-readable --compress --archive --hard-links --one-file-system --update --delete )

	if grep -q 'xattrs' <(rsync --help 2>&1)
	then
		rsync_options+=( --acls --xattrs )
	fi

	# Mac OS X and HFS+ Enhancements
	#   http://bombich.com/kb/ccc4/credits
	if [[ "$OSTYPE" == darwin* ]] && grep -q 'file-flags' <(rsync --help 2>&1)
	then
		rsync_options+=( --crtimes --fileflags --protect-decmpfs --force-change )
	fi

	local rsync_ssh="ssh -p ${port} -i ${ssh_key}"

	rsync ${rsync_options} -e ${rsync_ssh} ${path_deploy_from}/${dir_local_stage}/ ${username}@${hostname}:${path_deploy_to}/${dir_deploy_cache} &&

	echo "\n-----> Cached"
}

#
# ssh_cmd_stage
#   Make public
#

ssh_cmd_stage()
{
cat << EOF
# Sanity checks
[[ ! -f "${path_deploy_to}/last_version" ]] && echo "
! ERROR: Can't determine the last version.
!
! Ensure that "${path_deploy_to}/last_version" exists and contains the correct version.
! You may need to run:
!
      rsync-deploy.zsh --init
!
" && exit 25

# Stage
echo "-----> Staging @ ${username}@${hostname}:${path_deploy_to}/${dir_local_stage}\n"

echo "-----> Build finished"
echo "-----> Moving build to ${dir_deploy_releases}/${num_version_current}"
cp -R "${path_deploy_to}/${dir_deploy_cache}/" "${path_deploy_to}/${dir_deploy_releases}/${num_version_current}"

echo "-----> Updating the current symlink"
ln -nfs "${path_deploy_to}/${dir_deploy_releases}/${num_version_current}" "${path_deploy_to}/current"

echo "${num_version_current}" >! "${path_deploy_to}/last_version"

echo "-----> Done. Deployed v${num_version_current}"
EOF
}

#
# ssh_cmd_cleanup
#   Remove old releases
#

ssh_cmd_cleanup()
{
cat << EOF
echo "-----> Cleaning up old releases (keeping ${keep_releases})\n"

cd ${path_deploy_to}/${dir_deploy_releases} &&
ls -1d [0-9]* | sort -rn | tail -n ${num_releases_remove} | xargs rm -rf {} || exit 45
EOF
}

#
# ssh_cmd_lock
#   Prevent simultaneous deployments
#

ssh_cmd_lock()
{
cat << EOF
# Ensure deploy path is accessible
cd "${path_deploy_to}" || (
  echo "
! ERROR: Not set up.
!
! The path '${path_deploy_to}' is not accessible on the server.
! You may need to run:
!
      rsync-deploy.zsh --init
!"

  false
) || exit 10

# Ensure rsync-deploy.zsh --init has successfully ran
if [ ! -d "${path_deploy_to}/${dir_deploy_releases}" ]
then
  echo "
! ERROR: Not set up.
!
! The directory '${path_deploy_to}/${dir_deploy_releases}' does not exist on the server.
! You may need to run:
!
      rsync-deploy.zsh --init
!" && exit 15
fi

# Check whether or not another deployment is ongoing
[[ -f "${path_deploy_to}/${lock_file}" ]] &&
	echo "
! ERROR: another deployment is ongoing.
!
! The lock-file '${lock_file}' was found.
! If no other deployment is ongoing, run
!
      rsync-deploy.zsh --unlock
!
! to delete the file and continue." && exit 20

echo "-----> Locking\n"

# Lock
touch "${path_deploy_to}/${lock_file}"
EOF
}

#
# ssh_cmd_unlock
#   Unlock after successful build
#

ssh_cmd_unlock()
{
cat << EOF
echo "-----> Unlocking\n"

rm -f "${path_deploy_to}/${lock_file}"
EOF
}

#
# ssh_cmd_rollback
#   Rollback to the previous release
#

ssh_cmd_rollback()
{
cat << EOF
echo "-----> Creating new symlink from the previous release: \n"

ls -Art "${path_deploy_to}/releases" | sort | tail -n 2 | head -n 1
ls -Art "${path_deploy_to}/releases" | sort | tail -n 2 | head -n 1 | xargs -I active ln -nfs "${path_deploy_to}/releases/active" "${path_deploy_to}/current"

echo "-----> Deleting current release: \n"

ls -Art "${path_deploy_to}/releases" | sort | tail -n 1
ls -Art "${path_deploy_to}/releases" | sort | tail -n 1 | xargs -I active rm -rf "${path_deploy_to}/releases/active"
EOF
}

#
# usage
#   Your friendly help section
#

usage()
{
cat <<- EOT

  Usage :  $0 [options] [--]

  If using .rsync-deploy-rc, run the script from the same directory.

  Options:
  -h|--help       Display this message
  -v|--version    Display script version

  -i|--init       Initialize the deploy location
  -d|--deploy     Deploy the site
  -r|--rollback   Rollback to a previous version of the site
  -u|--unlock     Remove lockfile

  Directory structure:
  /var/www/chauncey.io/ # path_deploy_to
   |-  cache/           # dir_deploy_cache - rsync to save bandwidth
   |-  current          # a symlink to the current release in releases/
   |-  deploy.lock      # lock_file - help prevent multiple ongoing deploys
   |-  last_version     # contains the number of the last release
   '-  releases/        # dir_deploy_releases - one subdir per release
       |- 1/
       |- 2/
       |- 3/
       '- ...
EOT
}

#
# getopts
#   Run the appropriate commands
#

while getopts ":druihv" opt
do
  case ${opt} in

	d|-deploy )
		get-server-variables &&
		deploy-rsync-cache &&
		ssh_cmd_stage | ssh_cmd &&
		ssh_cmd_cleanup | ssh_cmd &&
		ssh_cmd_unlock | ssh_cmd
		exit 0
		;;

	r|-rollback )
		ssh_cmd_rollback | ssh_cmd &&
		ssh_cmd_unlock | ssh_cmd
		exit 0

		;;
	u|-unlock )
		ssh_cmd_unlock | ssh_cmd
		exit 0
		;;

	i|-init )
		ssh_cmd_init_test &&
		ssh_cmd_init | ssh_cmd
		exit 0
		;;

	h|-help )
		usage
		exit 0
		;;

	v|-version )
		echo "$0 -- Version $__ScriptVersion"
		exit 0
		;;

	* )
		echo -e "\n  Option does not exist : $OPTARG\n"
		usage
		exit 1
		;;

  esac
done
shift $(($OPTIND-1))

#
# Unset variables
#

unset deploy-rsync-cache
unset get-server-variables
unset ssh_cmd_cleanup
unset ssh_cmd_init
unset ssh_cmd_init_test
unset ssh_cmd_rollback
unset ssh_cmd_stage
unset ssh_cmd_unlock

