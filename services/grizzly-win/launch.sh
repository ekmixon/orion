#!/bin/sh
set -e -x

retry () {
  i=0
  while [ $i -lt 9 ]
  do
    "$@" && return
    sleep 30
    i="${i+1}"
  done
  "$@"
}

status () {
  if [ -n "$TASKCLUSTER_FUZZING_POOL" ]
  then
    python -m TaskStatusReporter --report "$@" || true
  fi
}

powershell -ExecutionPolicy Bypass -NoProfile -Command "Set-MpPreference -DisableRealtimeMonitoring \$true"

set +x
curl --retry 5 -L "$TASKCLUSTER_PROXY_URL/secrets/v1/secret/project/fuzzing/google-logging-creds" | python -c "import json,sys;json.dump(json.load(sys.stdin)['secret']['key'],open('google_logging_creds.json','w'))"
set -x
cat > td-agent-bit.conf << EOF
[SERVICE]
    Daemon       Off
    Log_File     $USERPROFILE\\td-agent-bit.log
    Log_Level    info
    Parsers_File $USERPROFILE\\td-agent-bit\\conf\\parsers.conf
    Plugins_File $USERPROFILE\\td-agent-bit\\conf\\plugins.conf

[INPUT]
    Name tail
    Path $USERPROFILE\\logs\\live.log,$USERPROFILE\\grizzly-auto-run\\screenlog.*
    Path_Key file
    Key message
    Refresh_Interval 5
    Read_from_Head On
    Skip_Long_Lines On
    Buffer_Max_Size 1M
    DB td-grizzly-logs.pos

[FILTER]
    Name rewrite_tag
    Match tail.*
    Rule \$file screenlog.([0-9]+)$ screen\$1.log false
    Rule \$file ([^\\\\]+)$ \$1 false

[FILTER]
    Name record_modifier
    Match *
    Record host task-${TASK_ID}-run-${RUN_ID}
    Record pool ${TASKCLUSTER_FUZZING_POOL-unknown}
    Remove_key file

[OUTPUT]
    Name stackdriver
    Match *
    google_service_credentials $USERPROFILE\\google_logging_creds.json
    resource global

[OUTPUT]
    Name file
    Match screen*.log
    Path $USERPROFILE\\logs\\
    Format template
    Template {time} {message}
EOF
./td-agent-bit/bin/fluent-bit.exe -c td-agent-bit.conf &

# Get fuzzmanager configuration from TC
set +x
curl --retry 5 -L "$TASKCLUSTER_PROXY_URL/secrets/v1/secret/project/fuzzing/fuzzmanagerconf" | python -c "import json,sys;open('.fuzzmanagerconf','w').write(json.load(sys.stdin)['secret']['key'])"
set -x

# Update fuzzmanager config for this instance
mkdir -p signatures
cat >> .fuzzmanagerconf << EOF
sigdir = $USERPROFILE\\signatures
tool = bearspray
EOF

# setup-fuzzmanager-hostname
name="task-${TASK_ID}-run-${RUN_ID}"
echo "Using '$name' as hostname." >&2
echo "clientid = $name" >>.fuzzmanagerconf
chmod 0600 .fuzzmanagerconf

status "Setup: cloning bearspray"

# Get deployment key from TC
mkdir -p .ssh
set +x
curl --retry 5 -L "$TASKCLUSTER_PROXY_URL/secrets/v1/secret/project/fuzzing/deploy-bearspray" | python -c "import json,sys;open('.ssh/id_ecdsa.bearspray','w',newline='\\n').write(json.load(sys.stdin)['secret']['key'])"
set -x

cat << EOF >> .ssh/config

Host bearspray
HostName github.com
IdentitiesOnly yes
IdentityFile $USERPROFILE\\.ssh\\id_ecdsa.bearspray
EOF

# Checkout bearspray
git init bearspray
cd  bearspray
git remote add origin git@bearspray:MozillaSecurity/bearspray.git
retry git fetch -q --depth 1 --no-tags origin HEAD
git -c advice.detachedHead=false checkout FETCH_HEAD
cd ..

status "Setup: installing bearspray"
retry python -m pip install -U -e bearspray

status "Setup: launching bearspray"
python -m bearspray
