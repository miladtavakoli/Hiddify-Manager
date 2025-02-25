#!/bin/bash
cd $(dirname -- "$0")
source ./common/utils.sh
NAME="0-install"
LOG_FILE="$(log_file $NAME)"

# Fix the installation directory
if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-server/" ]; then
        mv /opt/hiddify-server /opt/hiddify-manager
        ln -s /opt/hiddify-manager /opt/hiddify-server
fi
if [ ! -d "/opt/hiddify-manager/" ] && [ -d "/opt/hiddify-config/" ]; then
        mv /opt/hiddify-config/ /opt/hiddify-manager/
        ln -s /opt/hiddify-manager /opt/hiddify-config
fi

export DEBIAN_FRONTEND=noninteractive
if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi
function main() {
        update_progress "Please wait..." "We are going to install Hiddify..." 0
        export ERROR=0

        if [ "$MODE" != "apply_users" ]; then
                clean_files
                update_progress "Installing..." "Common Tools and Requirements" 2
                runsh install.sh common
                install_run other/redis
                install_run other/mysql
                install_python

                # Because we need to generate reality pair in panel
                # is_installed xray || bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.8.4

                install_run hiddify-panel
        fi

        # source common/set_config_from_hpanel.sh
        update_progress "HiddifyPanel" "Reading Configs from Panel..." 5
        set_config_from_hpanel

        update_progress "Applying Configs" "..." 8

        bash common/replace_variables.sh

        if [ "$MODE" != "apply_users" ]; then
                bash ./other/deprected/remove_deprecated.sh
                update_progress "Configuring..." "System and Firewall settings" 10
                runsh run.sh common

                update_progress "installing..." "Nginx" 15
                install_run nginx

                update_progress "installing..." "Haproxy for Spliting Traffic" 20
                install_run haproxy

                update_progress "installing..." "Getting Certificates" 30
                install_run acme.sh

                update_progress "installing..." "Personal SpeedTest" 35
                install_run other/speedtest

                update_progress "installing..." "Telegram Proxy" 40
                install_run other/telegram $ENABLE_TELEGRAM

                update_progress "installing..." "FakeTlS Proxy" 45
                install_run other/ssfaketls $ENABLE_SS

                # update_progress "installing..." "V2ray WS Proxy" 50
                # install_run other/v2ray $ENABLE_V2RAY

                update_progress "installing..." "SSH Proxy" 55
                install_run other/ssh $ssh_server_enable

                update_progress "installing..." "ShadowTLS" 60
                install_run other/shadowtls $ENABLE_SHADOWTLS

                update_progress "installing..." "Xray" 70
                install_run xray

                update_progress "installing..." "Warp" 75
                #$([ "$WARP_MODE" != 'disable' ] || echo "false")
                install_run other/warp

                update_progress "installing..." "Wireguard" 85
                install_run other/wireguard

        fi

        update_progress "installing..." "Singbox" 80
        install_run singbox

        update_progress "installing..." "Almost Finished" 90

        echo "---------------------Finished!------------------------"
        remove_lock $NAME
        if [ "$MODE" != "apply_users" ]; then
                systemctl kill -s SIGTERM hiddify-panel
        fi
        systemctl start hiddify-panel
        update_progress "installing..." "Done" 100

}

function clean_files() {
        rm -rf log/system/xray*
        rm -rf /opt/hiddify-manager/xray/configs/*.json
        rm -rf /opt/hiddify-manager/singbox/configs/*.json
        rm -rf /opt/hiddify-manager/haproxy/*.cfg
        find ./ -type f -name "*.template" -exec rm -f {} \;
}

function cleanup() {
        error "Script interrupted. Exiting..."
        # disable_ansii_modes
        remove_lock $NAME
        exit 9
}

# Trap the Ctrl+C signal and call the cleanup function
trap cleanup SIGINT

function set_config_from_hpanel() {
        (cd hiddify-panel && python3 -m hiddifypanel all-configs) >current.json
        chmod 600 current.json
        if [[ $? != 0 ]]; then
                error "Exception in Hiddify Panel. Please send the log to hiddify@gmail.com"
                exit 4
        fi

        export SERVER_IP=$(curl --connect-timeout 1 -s https://v4.ident.me/)
        export SERVER_IPv6=$(curl --connect-timeout 1 -s https://v6.ident.me/)
}

function install_run() {
        echo "==========================================================="
        if [ "$DO_NOT_INSTALL" != "true" ];then
                runsh install.sh $@
                if [ "$MODE" != "apply_users" ]; then
                        systemctl daemon-reload
                fi
        fi
        runsh run.sh $@
        echo "==========================================================="
}

function runsh() {
        command=$1
        if [[ $3 == "false" ]]; then
                command=uninstall.sh
        fi
        pushd $2 >>/dev/null
        # if [[ $? != 0]];then
        #         echo "$2 not found"
        # fi
        if [[ $? == 0 && -f $command ]]; then

                echo "===$command $2"
                bash $command
        fi
        popd >>/dev/null
}

if [[ " $@ " == *" --no-gui "* ]]; then
        set -- "${@/--no-gui/}"
        export MODE="$1"
        set_lock $NAME
        if [[ " $@ " == *" --no-log "* ]]; then
                set -- "${@/--no-log/}"
                main
        else
                main |& tee $LOG_FILE
        fi
        error_code=$?
        remove_lock $NAME
else
        show_progress_window --subtitle $(get_installed_config_version) --log $LOG_FILE ./install.sh $@ --no-gui --no-log
        error_code=$?
        if [[ $error_code != "0" ]]; then
                # echo less -r -P"Installation Failed! Press q to exit" +G "$log_file"
                msg_with_hiddify "Installation Failed! $error_code"
        else
                msg_with_hiddify "The installation has successfully completed."
                check_hiddify_panel $@ |& tee -a $LOG_FILE
        fi
fi

exit $error_code
