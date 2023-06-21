#!/usr/bin/env bash
set -u

### VARIABLES
_arg_package_manager="${COMPUTER_PACKAGE_MANAGER:-macports}"
_arg_check="off"

mas_version="1.8.6"
xcode_app_id="497799835"
macports_version="2.8.1"
macports_python_version="311"

### FUNCTIONS
# string formatters
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi

tty_mkbold() { tty_escape "1;$1"; }
tty_underline="$(tty_escape "4;39")"
tty_blue="$(tty_escape '0;34')"
tty_blue_bold="$(tty_mkbold 34)"
tty_magenta="$(tty_escape '0;35')"
tty_cyan="$(tty_mkbold 36)"
tty_red="$(tty_mkbold 31)"
tty_yellow="$(tty_escape '0;33')"
tty_yellow_bold="$(tty_mkbold 33)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"

shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"; do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue_bold}==>${tty_reset} %s\n" "$(shell_join "$@")"
}

yohai() {
  printf "${tty_blue_bold}==>${tty_bold} %s\n" "$(shell_join "$@")"
}

sudohai() {
  printf "${tty_blue_bold}==>${tty_magenta} %s${tty_reset}\n" "$(shell_join "$@")"
}

info() {
  printf "${tty_blue_bold}==>${tty_yellow_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")"
}

abort() {
  printf "%s\n" "$1"
  exit 1
}

die()
{
  local _ret="${2:-1}"
  test "${_PRINT_HELP:-no}" = yes && print_help >&2
  echo "$1" >&2
  exit "${_ret}"
}

begins_with_short_option()
{
  local first_option all_short_options='ph'
  first_option="${1:0:1}"
  test "$all_short_options" = "${all_short_options/$first_option/}" && return 1 || return 0
}

print_help()
{
  printf '%s\n' "Manage your computer like a pro. Currently supports macOS only."
  printf 'Usage: %s [-p|--package-manager <arg>] [-c|--(no-)check] [-h|--help]\n' "$0"
  printf '\t%s:    %s\n\t\t\t\t  %s\n' "-p, --package-manager" "Package manager to use (options: homebrew, macports). You can also set this" "using the environment variable COMPUTER_PACKAGE_MANAGER (default: 'macports')"
  printf '\t%s:  %s\n' "-c, --check, --no-check" "Check mode (off by default)"
  printf '\t%s:\t\t  %s\n' "-h, --help" "Prints help"
}

parse_commandline()
{
  while test $# -gt 0
  do
    _key="$1"
    case "$_key" in
      -p|--package-manager)
        test $# -lt 2 && die "Missing value for the optional argument '$_key'." 1
        _arg_package_manager="$2"
        shift
        ;;
      --package-manager=*)
        _arg_package_manager="${_key##--package-manager=}"
        ;;
      -p*)
        _arg_package_manager="${_key##-p}"
        ;;
      -c|--no-check|--check)
        _arg_check="on"
        test "${1:0:5}" = "--no-" && _arg_check="off"
        ;;
      -c*)
        _arg_check="on"
        _next="${_key##-c}"
        if test -n "$_next" -a "$_next" != "$_key"
        then
          { begins_with_short_option "$_next" && shift && set -- "-c" "-${_next}" "$@"; } || die "The short option '$_key' can't be decomposed to ${_key:0:2} and -${_key:2}, because ${_key:0:2} doesn't accept value and '-${_key:2:1}' doesn't correspond to a short option."
        fi
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      -h*)
        print_help
        exit 0
        ;;
      *)
        _PRINT_HELP=yes die "FATAL ERROR: Got an unexpected argument '$1'" 1
        ;;
    esac
    shift
  done
}

version_gt() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -gt "${2#*.}" ]]
}
version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}
version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

major_minor() {
  echo "${1%%.*}.$(
    x="${1#*.}"
    echo "${x%%.*}"
  )"
}

execute() {
  if check_mode; then
    info "CHECK MODE: $@"
    return
  fi

  if ! "$@"; then
    abort "$(printf "Failed during: %s" "$(shell_join "$@")")"
  fi
}

have_sudo_access() {
  if check_mode; then
    return 1
  fi

  local -a args
  if [[ -n "${SUDO_ASKPASS-}" ]]; then
    args=("-A")
  elif [[ -n "${NONINTERACTIVE-}" ]]; then
    args=("-n")
  fi

  if [[ -z "${HAVE_SUDO_ACCESS-}" ]]; then
    if [[ -n "${args[*]-}" ]]; then
      SUDO="/usr/bin/sudo ${args[*]}"
    else
      SUDO="/usr/bin/sudo"
    fi

    ${SUDO} -v && ${SUDO} -l mkdir &>/dev/null

    HAVE_SUDO_ACCESS="$?"
  fi

  return "$HAVE_SUDO_ACCESS"
}

execute_sudo() {
  local -a args=("$@")

  sudohai "SUDO: ${args[@]}"

  if have_sudo_access; then
    if [[ -n "${SUDO_ASKPASS-}" ]]; then
      args=("-A" "${args[@]}")
    fi
    args=("/usr/bin/sudo" "${args[@]}")
    execute "${args[@]}"
  else
    execute "${args[@]}"
  fi
}

macports() {
  local -a args=("$@")
  execute_sudo "/opt/local/bin/port" "${args[@]}"
}

should_install_command_line_tools() {
  ! [[ -e "/Library/Developer/CommandLineTools/usr/bin/git" ]]
}

should_install_xcode() {
  ! [[ -e "/Applications/Xcode.app/Contents/Developer/usr/bin/git" ]]
}

should_install_macports() {
  if use_macports; then
    return 1
  else 
    ! [[ -e "/opt/local/bin/port" ]]
  fi
}

should_install_mas() {
  if [[ -e "/usr/local/bin/mas" ]]; then
    mas_cli='/usr/local/bin/mas'
    return 1
  elif [[ -e "/opt/local/bin/mas" ]]; then
    mas_cli='/opt/local/bin/mas'
    return 1
  else
    mas_cli='/usr/local/bin/mas'
    return
  fi
}

check_mode() {
  [[ "$_arg_check" = "on" ]]
}

should_install_port() {
  local port_status="$(/opt/local/bin/port -q installed $1 | sed -e 's/^[ \t]*//')"
  ! [[ $port_status == $1* ]]
}

should_install_rosetta() {
 [[ "$(uname -m)" == "arm64" ]] && ! [[ -e "/Library/Apple/usr/libexec/oah/libRosettaRuntime" ]]
}

install_port() {
  if should_install_port $1; then
    ohai "Installing port $1"
    macports "-N" "install" $1
  else
    ohai "Port $1 is installed"
  fi
}

port_select() {
  macports "select" "--set" $1 $2
}

mas_install() {
  ohai "Installing $1 from the Mac App Store"
  execute $mas_cli "install" $2
}

should_install_homebrew() {
  ! [[ -e "/usr/local/bin/brew" ]]
}

homebrew() {
  local -a args=("$@")
  execute "/usr/local/bin/brew" "${args[@]}"
}

should_install_formula() {
  local formula_status="$(/usr/local/bin/brew list -1 2>/dev/null | grep "^${1}$")"
  ! [[ $formula_status == $1 ]]
}

install_formula() {
  if should_install_formula $1; then
    ohai "Brewing $1"
    homebrew "install" $1
  else
    ohai "Formula $1 is installed"
  fi
}

install_package() {
  local port="${1:-}"
  local formula="${2:-}"

  if [[ "${_arg_package_manager}" = 'macports' && "$port" != "" ]]; then
    install_port $1
  elif [[ "${_arg_package_manager}" = 'homebrew' && "$formula" != "" ]]; then
    install_formula $2
  fi
}

use_homebrew() {
  [[ "${_arg_package_manager}" = 'homebrew' ]]
}

use_macports() {
  [[ "${_arg_package_manager}" = 'macports' ]]
}

# SCRIPT

parse_commandline "$@"

macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"

processor="$(uname -m)"

if version_ge "${macos_version}" "13.0"; then
  macports_pkg_suffix="13-Ventura"
elif version_ge "${macos_version}" "12.0"; then
  macports_pkg_suffix="12-Monterey"
elif version_ge "${macos_version}" "11.0"; then
  macports_pkg_suffix="11-BigSur"
else
  abort "Sorry, macOS BigSur or higher is required, exiting"
fi

if ! [[ "$_arg_package_manager" = "macports" || "$_arg_package_manager" = "homebrew" ]]; then
  abort "The package manager '${_arg_package_manager}' is not supported. Valid options: macports, homnebrew"
fi

yohai "Setting up your computer"
yohai "Your macOS version: $macos_version"
yohai "Package manager: ${_arg_package_manager}"
yohai "Processor type: ${processor}"

if check_mode; then
  info "Running in check mode, no changes will be made"
fi

if [[ "$processor" == "arm64" ]]; then
  ohai "Checking if Rosetta is installed..."

  if should_install_rosetta; then
    ohai "Installing Rosetta"
    execute_sudo "softwareupdate" "--install-rosetta" "--agree-to-license"
  else
    yohai "Rosetta is installed"
  fi
fi

ohai "Checking for MAS..."

reinstall_mas=0

if should_install_mas; then
  if use_macports && ! should_install_macports; then
    install_package "mas" "mas"
    uninstall_mas=0
  else
    ohai "Installing mas from github"

    execute "curl" "-L" "https://github.com/mas-cli/mas/releases/download/v${mas_version}/mas.pkg" "-o" "mas.pkg"

    execute_sudo "/usr/sbin/installer" "-verbose" "-pkg" "mas.pkg" "-target" "/"

    execute "rm" "mas.pkg"

    reinstall_mas=1
  fi
else
  yohai "MAS is installed"
fi

ohai "Checking for Xcode..."
if should_install_xcode; then
  mas_install "Xcode" "497799835"

  ohai "Accepting Xcode license"

  execute_sudo "/usr/bin/xcodebuild" "-license" "accept"

  execute_sudo "/usr/bin/xcode-select" "--install"
else
  yohai "Xcode is installed"
fi

if use_macports; then
  ohai "Checking for MacPorts..."
  if should_install_macports; then
    ohai "Installing MacPorts"

    macports_download_url="https://github.com/macports/macports-base/releases/download/v${macports_version}/MacPorts-${macports_version}-${macports_pkg_suffix}.pkg"

    execute "curl" "-L" $macports_download_url "-o" "macports.pkg"

    execute_sudo "/usr/sbin/installer" "-verbose" "-pkg" "macports.pkg" "-target" "/"

    execute "rm" "macports.pkg"
  else
    yohai "MacPorts is installed, updating"
    macports "selfupdate"
  fi
fi

if use_homebrew; then
  ohai "Checking for Homebrew..."
  if should_install_homebrew; then
    execute "curl" "-fsSL" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "-o" "brew_install.sh"
    execute "chmod" "+x" "brew_install.sh"
    execute "/bin/bash" "-c" "./brew_install.sh"
    execute "rm" "brew_install.sh"
  else
    yohai "Homebrew is installed, updating"
    homebrew "update"
  fi
fi

if [ "$reinstall_mas" = 1 ]; then
  ohai "Uninstalling mas (will be reinstalled using ${_arg_package_manager})"

  execute_sudo "rm" "-rf" "/usr/local/Frameworks/MasKit.framework"

  execute_sudo "rm" "/usr/local/bin/mas"

  install_package "mas" "mas"
fi

install_package "curl-ca-bundle"
install_package "python${macports_python_version}" "python@3.11"
install_package "py${macports_python_version}-pip"
install_package "py${macports_python_version}-setuptools"
install_package "py${macports_python_version}-wheel"
install_package "py${macports_python_version}-virtualenv" "virtualenv"
install_package "py${macports_python_version}-ansible" "ansible"

if use_macports; then
  port_select "python" "python${macports_python_version}"
  port_select "python3" "python${macports_python_version}"
  port_select "pip" "pip${macports_python_version}"
  port_select "pip3" "pip${macports_python_version}"
  port_select "virtualenv" "virtualenv${macports_python_version}"
  port_select "ansible" "py${macports_python_version}-ansible"
fi

#if use_homebrew; then
#  if check_mode; then
#    info "CHECK MODE: Add virtualenv and python3 to PATH"
#  else
#    PATH=$(homebrew "--prefix" "virtualenv"):$(homebrew "--prefix" "python@3.10"):$PATH
#  fi
#fi

if use_macports; then
  if check_mode; then
    info "CHECK MODE: Add /opt/local/bin and /opt/local/sbin to PATH"
  else
    export PATH=/opt/local/bin:/opt/local/sbin:$PATH
  fi
fi
