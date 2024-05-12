#!/bin/bash

# Create App Dir
mkdir -p "${STEAMAPPDIR}" || true

# Download Updates

if [[ "$STEAMAPPVALIDATE" -eq 1 ]]; then
    VALIDATE="validate"
else
    VALIDATE=""
fi

eval bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
				+login anonymous \
				+app_update "${STEAMAPPID}" "${VALIDATE}"\
				+quit

# steamclient.so fix
mkdir -p ~/.steam/sdk64
ln -sfT ${STEAMCMDDIR}/linux64/steamclient.so ~/.steam/sdk64/steamclient.so

# Install server.cfg
cp /etc/server.cfg "${STEAMAPPDIR}"/game/csgo/cfg/server.cfg

# Install hooks if they don't already exist
if [[ ! -f "${STEAMAPPDIR}/pre.sh" ]] ; then
    cp /etc/pre.sh "${STEAMAPPDIR}/pre.sh"
fi
if [[ ! -f "${STEAMAPPDIR}/post.sh" ]] ; then
    cp /etc/post.sh "${STEAMAPPDIR}/post.sh"
fi
if [[ ! -f "${STEAMAPPDIR}/helper/version.ini" ]] ; then
    mkdir "${STEAMAPPDIR}/helper/"
    cp /etc/version.ini "${STEAMAPPDIR}/helper/version.ini"
fi

# Download and extract custom config bundle
if [[ ! -z $CS2_CFG_URL ]]; then
    echo "Downloading config pack from ${CS2_CFG_URL}"
    wget -qO- "${CS2_CFG_URL}" | tar xvzf - -C "${STEAMAPPDIR}"
fi

# Download and extract metamod
if [ ! -f "${STEAMAPPDIR}/game/csgo/addons/metamod.vdf" ]; then
    METAMOD="https://mms.alliedmods.net/mmsdrop/2.0/mmsource-2.0.0-git1291-linux.tar.gz"
    wget -qO- "${METAMOD}" | tar xvzf - -C "${STEAMAPPDIR}/game/csgo/"
    sed -i '23i\\t\t\tGame\tcsgo/addons/metamod' "${STEAMAPPDIR}/game/csgo/gameinfo.gi"

fi

if [[ ! -z $CS2_UPDATE_CSS ]]; then
# Download CounterStrikeSharp Updates
    VERSION_FILE="${STEAMAPPDIR}/"helper/version.ini
    CSS_KEY="css"
    css_version=$(crudini --get "${VERSION_FILE}" "${CSS_KEY}" "version")
    Echo "css version " $css_version   

    # REPOs:
    REPO_CSS="roflmuffin/CounterStrikeSharp"

    # Fetch the latest release data using GitHub API
    LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$REPO_CSS/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
    echo $LATEST_RELEASE

    if [ "$LATEST_RELEASE" != "$css_version" ]; then
        echo "Newer version available: $LATEST_RELEASE"
        echo "Downloading $REPO_CSS $LATEST_RELEASE"
        wget -P "${STEAMAPPDIR}/" $(curl -L -s https://api.github.com/repos/roflmuffin/CounterStrikeSharp/releases/latest | grep -o -E "https://(.*)counterstrikesharp-with-runtime-build-(.*)linux(.*).zip")
        echo "Extracting $REPO_CSS $LATEST_RELEASE"
        unzip -o "${STEAMAPPDIR}/counterstrikesharp-with-runtime-build-${LATEST_RELEASE}-linux-*.zip" -d "${STEAMAPPDIR}"/game/csgo/
        rm counterstrikesharp-with-runtime-build-${LATEST_RELEASE}-linux-*.zip
        echo "Updating Version in INI $LATEST_RELEASE"
        crudini --set "${VERSION_FILE}" "${CSS_KEY}" "version" "$LATEST_RELEASE"   
    fi

fi

# Rewrite Config Files

sed -i -e "s/{{SERVER_HOSTNAME}}/${CS2_SERVERNAME}/g" \
       -e "s/{{SERVER_CHEATS}}/${CS2_CHEATS}/g" \
       -e "s/{{SERVER_HIBERNATE}}/${CS2_SERVER_HIBERNATE}/g" \
       -e "s/{{SERVER_PW}}/${CS2_PW}/g" \
       -e "s/{{SERVER_RCON_PW}}/${CS2_RCONPW}/g" \
       -e "s/{{TV_ENABLE}}/${TV_ENABLE}/g" \
       -e "s/{{TV_PORT}}/${TV_PORT}/g" \
       -e "s/{{TV_AUTORECORD}}/${TV_AUTORECORD}/g" \
       -e "s/{{TV_PW}}/${TV_PW}/g" \
       -e "s/{{TV_RELAY_PW}}/${TV_RELAY_PW}/g" \
       -e "s/{{TV_MAXRATE}}/${TV_MAXRATE}/g" \
       -e "s/{{TV_DELAY}}/${TV_DELAY}/g" \
       -e "s/{{SERVER_LOG}}/${CS2_LOG}/g" \
       -e "s/{{SERVER_LOG_MONEY}}/${CS2_LOG_MONEY}/g" \
       -e "s/{{SERVER_LOG_DETAIL}}/${CS2_LOG_DETAIL}/g" \
       -e "s/{{SERVER_LOG_ITEMS}}/${CS2_LOG_ITEMS}/g" \
       "${STEAMAPPDIR}"/game/csgo/cfg/server.cfg

if [[ ! -z $CS2_BOT_DIFFICULTY ]] ; then
    sed -i "s/bot_difficulty.*/bot_difficulty ${CS2_BOT_DIFFICULTY}/" "${STEAMAPPDIR}"/game/csgo/cfg/*
fi
if [[ ! -z $CS2_BOT_QUOTA ]] ; then
    sed -i "s/bot_quota.*/bot_quota ${CS2_BOT_QUOTA}/" "${STEAMAPPDIR}"/game/csgo/cfg/*
fi
if [[ ! -z $CS2_BOT_QUOTA_MODE ]] ; then
    sed -i "s/bot_quota_mode.*/bot_quota_mode ${CS2_BOT_QUOTA_MODE}/" "${STEAMAPPDIR}"/game/csgo/cfg/*
fi

# Switch to server directory
cd "${STEAMAPPDIR}/game/bin/linuxsteamrt64"

# Pre Hook
bash "${STEAMAPPDIR}/pre.sh"

# Construct server arguments

if [[ -z $CS2_GAMEALIAS ]]; then
    # If CS2_GAMEALIAS is undefined then default to CS2_GAMETYPE and CS2_GAMEMODE
    CS2_GAME_MODE_ARGS="+game_type ${CS2_GAMETYPE} +game_mode ${CS2_GAMEMODE}"
else
    # Else, use alias to determine game mode
    CS2_GAME_MODE_ARGS="+game_alias ${CS2_GAMEALIAS}"
fi

if [[ -z $CS2_IP ]]; then
    CS2_IP_ARGS=""
else
    CS2_IP_ARGS="-ip ${CS2_IP}"
fi

if [[ ! -z $SRCDS_TOKEN ]]; then
    SV_SETSTEAMACCOUNT_ARGS="+sv_setsteamaccount ${SRCDS_TOKEN}"
fi

# Start Server

if [[ ! -z $CS2_RCON_PORT ]]; then
    echo "Establishing Simpleproxy for ${CS2_RCON_PORT} to 127.0.0.1:${CS2_PORT}"
    simpleproxy -L "${CS2_RCON_PORT}" -R 127.0.0.1:"${CS2_PORT}" &
fi

echo "Starting CS2 Dedicated Server"
eval "./cs2" -dedicated \
        "${CS2_IP_ARGS}" -port "${CS2_PORT}" \
        -console \
        -usercon \
        -maxplayers "${CS2_MAXPLAYERS}" \
        "${CS2_GAME_MODE_ARGS}" \
        +mapgroup "${CS2_MAPGROUP}" \
        +map "${CS2_STARTMAP}" \
        +rcon_password "${CS2_RCONPW}" \
        "${SV_SETSTEAMACCOUNT_ARGS}" \
        +sv_password "${CS2_PW}" \
        +sv_lan "${CS2_LAN}" \
        "${CS2_ADDITIONAL_ARGS}"

# Post Hook
bash "${STEAMAPPDIR}/post.sh"
