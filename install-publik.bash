#!/bin/bash
#  _           _        _ _                   _     _ _ _    
# (_)_ __  ___| |_ __ _| | |      _ __  _   _| |__ | (_) | __
# | | '_ \/ __| __/ _` | | |_____| '_ \| | | | '_ \| | | |/ /
# | | | | \__ \ || (_| | | |_____| |_) | |_| | |_) | | |   < 
# |_|_| |_|___/\__\__,_|_|_|     | .__/ \__,_|_.__/|_|_|_|\_\
#                                |_|                         

# Global variables definition
APPLICATION="Publik (Entrouvert) installation"
STDOUT="stdout.log"
STDERR="stderr.log"
SUDO_PASSWORD=""
PUBLIK_DIRECTORY="publik-env"
declare -a DIALOG_VALUES
declare -a PROXY_SETTINGS

# Check requirements for this script, exits if any requirement is not met.
function check_requirements() {
    # Checks the presence of the sudo utility
    which "sudo" > /dev/null
    if [ $? -ne 0 ]
    then
        echo "This script requires the sudo command."
        exit 10
    fi

    # Checks the presence of the dialog utility
    which "dialog" > /dev/null
    if [ $? -ne 0 ]
    then
        echo "This script requires the dialog command."
        exit 10
    fi

    # Ensures we are on Debian or Ubuntu
    which "apt-get" > /dev/null
    if [ $? -ne 0 ]
    then
        echo "This script works only with Debian or Ubuntu."
        exit 10
    fi
}

# Run a dialog command. If the command has a return code not set to 0, it
# directly exits the current script.
#
# Global variables:
# - APPLICATION: the application title, will be written in background of screen
# - DIALOG_VALUES: this array will contain the value the user has input
function run_dialog() {
    local temporary_file=$(mktemp)
    local rc=0

    dialog --backtitle "$APPLICATION" "$@" 2> "$temporary_file"
    rc=$?

    readarray -t DIALOG_VALUES < "$temporary_file"
    rm -- "$temporary_file"

    if [ $rc -ne 0 ]
    then
        dialog --backtitle "$APPLICATION" --msgbox "Script aborted" 5 50
        exit 1
    fi        
}

# Run a command with the current user.
# Arguments:
# - 1: title
# - 2: progression function which converts command output to percentage
# - 3-*: command to execute
#
# Global variables:
# - STDERR: the file receiving the standard error stream
function run() {
    local title="$1"
    local progression="$2"
    shift 2

    LANG= "$@" 2>> $STDERR | $progression | run_dialog --gauge "$title" 0 80 0

    if [ "${PIPESTATUS[1]}" -ne 0 ]
    then
        run_dialog --tailbox "$STDERR" 25 80
        exit 1
    fi
}

# Run a command with the root user.
# Arguments:
# - 1: title
# - 2: progression function which converts command output to percentage
# - 3-*: command to execute
#
# Global variables:
# - SUDO_PASSWORD: the sudo password
# - STDERR: the file receiving the standard error stream
function run_sudo() {
    local title="$1"
    local progression="$2"
    shift 2

    printf "%s\n" "$SUDO_PASSWORD" \
        | LANG= sudo -S "$@" 2>> $STDERR \
        | $progression \
        | run_dialog --gauge "$title" 0 80 0

    if [ "${PIPESTATUS[1]}" -ne 0 ]
    then
        run_dialog --tailbox "$STDERR" 25 80
        exit 1
    fi
}

# Ask the user for the sudo password.
#
# Global variables:
# - SUDO_PASSWORD: this variable is set with the password
function ask_password() {
    run_dialog --insecure --passwordbox "Type in the SUDO password" 8 50
    SUDO_PASSWORD="${DIALOG_VALUES[0]}"
    unset DIALOG_VALUES
}

# Ask the user for the Publik directory.
#
# Global variables:
# - PUBLIK_DIRECTORY: this variable is set with the Publik directory
function ask_publik_directory() {
    run_dialog --inputbox "Directory to create" 8 50 "$PUBLIK_DIRECTORY"
    PUBLIK_DIRECTORY="${DIALOG_VALUES[0]}"
    unset DIALOG_VALUES

    if [ -d "$PUBLIK_DIRECTORY" ]
    then
        run_dialog --msgbox "$PUBLIK_DIRECTORY already exists!" 5 50
        exit 3
    fi
}

# Ask the user for the proxy settings.
#
# Global variables:
# - DIALOG_VALUES: contains the 4 default values (user, password, URL, port).
#                  On return, it will contain the values set by the user.
function ask_proxy() {
    run_dialog \
        --form "Proxy settings" 0 0 4 \
            "User"     1 1 "${DIALOG_VALUES[0]}" 1 10 20 0 \
            "Password" 2 1 "${DIALOG_VALUES[1]}" 2 10 20 0 \
            "URL"      3 1 "${DIALOG_VALUES[2]}" 3 10 50 0 \
            "Port"     4 1 "${DIALOG_VALUES[3]}" 4 10 6  0
}

# A progression filter for apt-get.
# This functions is meant to be used by the run and run_sudo functions.
function apt_progression() {
    sed --quiet --unbuffered '
        /Reading package lists/a15
        /Reading state information/a30
        /upgraded/a45
        /Reading database/a60
        /Preparing to unpack/a75
        /Setting up/a90
    '
    echo 100
}

# A progression filter for virtualenv.
# This functions is meant to be used by the run and run_sudo functions.
function virtualenv_progression() {
    sed --quiet --unbuffered '
        /Running virtualenv with/a20
        /New python executable in/a40
        /Also creating executable in/a60
        /Installing setuptools/a80
    '
    echo 100
}

# A progression filter for git.
# This functions is meant to be used by the run and run_sudo functions.
function git_progression() {
    sed --quiet --unbuffered '
        /Cloning into/a20
        /Checking connectivity/a80
    '
    echo 100
}

# A progression filter for pip install.
# This functions is meant to be used by the run and run_sudo functions.
function get_pip_progression() {
    sed --quiet --unbuffered '
        /Resolving/a10
        /Connecting to/a20
        /HTTP request sent/a30
        /Length:/a40
        /Saving to:/a50
        /written to stdout/a60
        /Collecting/a70
        /Installing collected packages/a80
        /Successfully installed/a90
    '
    echo 100
}

# A progression filter for gem install sass.
# This functions is meant to be used by the run and run_sudo functions.
function gem_sass_progression() {
    sed --quiet --unbuffered '
        /Building native extensions/a8
        /Successfully installed ffi/a16
        /Successfully installed rb-inotify/a24
        /Successfully installed rb-fsevent/a32
        /Successfully installed sass-listen/a40
        /Successfully installed sass-[^l]/a48
        /Installing ri documentation for ffi/a56
        /Installing ri documentation for rb-fsevent/a64
        /Installing ri documentation for rb-inotify/a72
        /Installing ri documentation for sass-[^l]/a80
        /Installing ri documentation for sass-listen/a88
        /gems installed/a96
    '
    echo 100
}

# A progression filter for pip install -e .
# This functions is meant to be used by the run and run_sudo functions.
function pip_requirements_progression() {
    local requirements
    local counter
    local req_count
    local found

    local re_start='^(Requirement already satisfied:|Collecting) '
    local re_end='[ ,<>=]'

    readarray -t requirements < <(get_python_requirements "setup.py")
    req_count="${#requirements[@]}"

    while read line
    do
        found=$(
            for requirement in "${requirements[@]}"
            do
                if [[ $line =~ $re_start$requirement$re_end ]]
                then
                    printf "x"
                    break
                fi
            done
        )

        if [ "$found" = "x" ]
        then
            counter=$((counter + 1))
            printf "%d\n" $((100 * counter / (req_count + 1) ))
        fi
    done
    echo 100
}

# A progression filter for ./manage.py migrate.
# This functions is meant to be used by the run and run_sudo functions.
function manage_migrate_progression() {
    local re_start='^ *Applying '
    local re_end='\.\.\. OK$'

    readarray -t steps < <(manage_migrate_dependencies | sort | uniq)
    step_count="${#steps[@]}"

    while read line
    do
        found=$(
            for step in "${steps[@]}"
            do
                if [[ $line =~ $re_start$step$re_end ]]
                then
                    printf "x"
                    break
                fi
            done
        )

        if [ "$found" = "x" ]
        then
            counter=$((counter + 1))
            printf "%d\n" $((100 * counter / (step_count + 1) ))
        fi
    done
    echo 100
}

# Find all migration steps that ./manage.py migrate will go through
function manage_migrate_dependencies() {
    local filter_files='/migrations/[0-9][0-9][0-9][0-9]_'
    local path_to_id="s/^.*\/\([^/]*\)\/migrations\/\([^/]*\)\.py$/\1.\2/gp"
    local dep_to_id="
        /^ *dependencies *= *\\[/,/^ *\\]$/{
            s/^ *('\([^']*\)'.*'\([^']*\)').*$/\1.\2/gp
        }
    "

    # Retrieve IDs from dependencies inside migration files
    find . -name "*.py" \
        | grep "$filter_files" \
        | xargs cat -- \
        | sed --quiet "$dep_to_id"

    # Retrieve IDs from migration files of the current application
    find . -name "*.py" | grep "$filter_files" | sed --quiet "$path_to_id"

    # Retrieve IDs from frameworks and other base packages
    find ../lib -name "*.py" | grep "$filter_files" | sed --quiet "$path_to_id"
}

# Retrieve requirements from a setup.py file
#
# It outputs the list of requirements in reverse order to help differentiate,
# for example, django from django-ckeditor.
#
# Arguments:
# - 1: the path to a setup.py file
function get_python_requirements() {
    local setuppy="$1"
    cat "$setuppy" \
        | sed --quiet '/^ *install_requires/,/^ *\],/p' \
        | grep --perl-regexp --only-matching "(?<=')[^ ,'<>=]+" \
        | sort --reverse
}

# Retrieve proxy settings from the http_proxy environment variable.
#
# This function only considers the following cases:
# - user + password + URL
# - user + password + URL + port
# - URL
# - URL + port
#
# It outputs 4 lines in the following order:
# - user name
# - user password
# - URL of proxy server
# - port of the proxy server
function get_proxy_settings() {
    local re='^http://(([^@:/]+):([^@:/]+)@)?([^@:/]+)(:([0-9]+))?'
    if [[ $http_proxy =~ $re ]]
    then
        printf "%s\n%s\n%s\n%s\n" \
               "${BASH_REMATCH[2]}" \
               "${BASH_REMATCH[3]}" \
               "${BASH_REMATCH[4]}" \
               "${BASH_REMATCH[6]}"
    fi
}

# Set proxy settings.
#
# This function sets and exports http_proxy, https_proxy and all_proxy
# environment variables.
#
# Arguments:
# - 1: user name (optional)
# - 2: password (optional if user name is empty)
# - 3: url
# - 4: port (optional)
function set_proxy_settings() {
    local user="$1"
    local password="$2"
    local url="$3"
    local port="$4"
    local proxy_url=""

    if [ "$user" ]
    then
        proxy_url="$user:$password@"
    fi

    if [ "$port" ]
    then
        proxy_url="$proxy_url$url:$port/"
    else
        proxy_url="$proxy_url$url/"
    fi

    export http_proxy="http://$proxy_url"
    export https_proxy="https://$proxy_url"
    export all_proxy="https://$proxy_url"
}

# Show introduction with a yes/no dialog allowing the user to abort the script.
function show_introduction() {
    run_dialog --yesno \
        "This script will install Publik (Entr'ouvert).

The following packages will be installed, if needed, in your system:
- Git
- Python VirtualEnv
- Ruby + Ruby dev
- Sass

Do you wish to continue?" \
        0 0
}

# Since this command contains a pipe, it can not be used directly, by the
# run or run_sudo function, that’s why it is written in a function.
function install_new_pip() {
    wget -O - https://bootstrap.pypa.io/get-pip.py | python
}

#  __  __       _                                                   
# |  \/  | __ _(_)_ __    _ __  _ __ ___   __ _ _ __ __ _ _ __ ___  
# | |\/| |/ _` | | '_ \  | '_ \| '__/ _ \ / _` | '__/ _` | '_ ` _ \ 
# | |  | | (_| | | | | | | |_) | | | (_) | (_| | | | (_| | | | | | |
# |_|  |_|\__,_|_|_| |_| | .__/|_|  \___/ \__, |_|  \__,_|_| |_| |_|
#                        |_|              |___/                     

check_requirements

show_introduction

ask_password

# Ask for proxy settings if the http_proxy variable has been set
if [ "$http_proxy" ]
then
    readarray -t DIALOG_VALUES < <(get_proxy_settings)
    ask_proxy
    set_proxy_settings \
        "${DIALOG_VALUES[0]}" \
        "${DIALOG_VALUES[1]}" \
        "${DIALOG_VALUES[2]}" \
        "${DIALOG_VALUES[3]}"
fi

ask_publik_directory

run_sudo "Installing Git" \
    apt_progression \
    apt-get -y install git

run_sudo "Installing Python VirtualEnv" \
    apt_progression \
    apt-get -y install python-virtualenv

run_sudo "Installing Python C header files (needed for Gadjo)" \
    apt_progression \
    apt-get -y install python-dev

run_sudo "Installing Ruby (needed for Sass)" \
    apt_progression \
    apt-get -y install ruby ruby-dev

run_sudo "Installing Sass" \
    gem_sass_progression \
    gem install sass

run "Creating virtual environment in $PUBLIK_DIRECTORY" \
    virtualenv_progression \
    virtualenv "$PUBLIK_DIRECTORY"

# We are now running in a Python virtual environment!
cd "$PUBLIK_DIRECTORY"
source bin/activate

# Debian/Ubuntu has a very old version of pip, we need a more recent version!
run "Retrieving a current version of pip" \
    get_pip_progression \
    install_new_pip

run "Cloning Combo repository in $PUBLIK_DIRECTORY/combo" \
    git_progression \
    git clone http://repos.entrouvert.org/combo.git

# Adding STATIC_ROOT settings for ./manage.py collectstatic
directory=$(readlink -e "$1")
printf "\nSTATIC_ROOT = '%s'\n" \
    "$(readlink -e "$PUBLIK_DIRECTORY")/static" \
    >> combo/combo/settings.py

cd combo
run "Installing Combo requirements" \
    pip_requirements_progression \
    pip install -e .
cd ..

run "Cloning WCS repository in $PUBLIK_DIRECTORY/wcs" \
    git_progression \
    git clone http://repos.entrouvert.org/wcs.git

cd wcs
run "Installing WCS requirements" \
    pip_requirements_progression \
    pip install -e .
cd ..

cd combo
run "Initializing the database (manage.py migrate)" \
    manage_migrate_progression \
    ./manage.py migrate
cd ..

