#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

function log {
    local msg="$1"
    echo "$(date -Iseconds) $msg" >&2
}

# NB all command executions (including input and output) are saved in
#    AWS Systems Manager, Run Command, Command history, and cannot be deleted
#    by the user, instead, its automatically deleted after 30 days. longer
#    retention periods are possible (e.g. by sending them to cloudwatch or a
#    s3 bucket).
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/walkthrough-cli.html
# see https://docs.aws.amazon.com/cli/latest/reference/ssm/
# see aws ssm describe-document --name AWS-RunShellScript --query "Document.Parameters[*]"
# see aws ssm list-commands --instance-id i-00000000000000000
# see aws ssm list-command-invocations --details --instance-id i-00000000000000000
function execute_ssm_command {
    local instance_id="$1"
    local title="$2"
    local cmd="$3"

    log "Sending the $title command..."
    local command_parameters="$(jq -n --compact-output --arg cmd "$cmd" '{"commands":[$cmd]}')"
    local command_id="$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name AWS-RunShellScript \
        --parameters "$command_parameters" \
        --query Command.CommandId \
        --output text)"

    # NB we use || true to be able to get the command stderr, stdout, and exit code.
    # NB without it, it will fail with the following error and stop the script:
    #       Waiter CommandExecuted failed: Waiter encountered a terminal failure state: For expression "Status" we matched expected path: "Failed"
    log "Waiting for the $title command ($command_id) to execute..."
    aws ssm wait command-executed \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        || true

    log "Getting the $title command ($command_id) stderr..."
    aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query StandardErrorContent \
        --output text \
        | awk 'NF { found=1 } found' \
        >&2

    log "Getting the $title command ($command_id) stdout..."
    aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query StandardOutputContent \
        --output text

    log "Getting the $title command ($command_id) exit code..."
    local response_code="$(aws ssm get-command-invocation \
        --instance-id "$instance_id" \
        --command-id "$command_id" \
        --query ResponseCode \
        --output text)"

    if ! [[ "$response_code" =~ ^[0-9]+$ ]]; then
        response_code=1
    fi

    return $response_code
}

function wait_for_ready {
    local instance_id="$1"

    local wait_command="while ! (systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service && cloud-init status --wait); do sleep 5; done"

    execute_ssm_command "$instance_id" "wait for ready" "$wait_command"
}

instance_id="$1"
command="bash -c 'for f in /etc/ssh/ssh_host_*_key.pub; do cat \"\$f\"; done'"

wait_for_ready "$instance_id"

sshd_public_keys="$(execute_ssm_command "$instance_id" "get sshd public keys" "$command")"

jq -n --compact-output --arg keys "$sshd_public_keys" '{"sshd_public_keys":$keys}'
