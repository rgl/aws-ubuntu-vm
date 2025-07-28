# About

[![Lint](https://github.com/rgl/aws-ubuntu-vm/actions/workflows/lint.yml/badge.svg)](https://github.com/rgl/aws-ubuntu-vm/actions/workflows/lint.yml)

An example Ubuntu VM running in a AWS EC2 Instance.

This will:

* Create a VPC.
  * Configure a Internet Gateway.
* Create a Systems Manager ([aka SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html#service-naming-history)) Parameter.
* Create a EC2 Instance.
  * Assign a Public IP address.
  * Assign a IAM Role.
    * Include the [AmazonSSMManagedInstanceCore Policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html).
  * Initialize with cloud-init.
    * Configure the guest firewall.
    * Install a example application.
      * Get the [Instance Identity Document](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-identity-documents.html) from the [EC2 Instance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html).
      * Get a Parameter from the [Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html).
      * Get the [Instance (IAM) Role Credentials](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#instance-metadata-security-credentials).
  * Wait for the instance to be ready.

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Set the AWS Account credentials using SSO, e.g.:

```bash
# set the account credentials.
# NB the aws cli stores these at ~/.aws/config.
# NB this is equivalent to manually configuring SSO using aws configure sso.
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-manual
# see https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html#sso-configure-profile-token-auto-sso
cat >secrets.sh <<'EOF'
# set the environment variables to use a specific profile.
# NB use aws configure sso to configure these manually.
# e.g. use the pattern <aws-sso-session>-<aws-account-id>-<aws-role-name>
export aws_sso_session='example'
export aws_sso_start_url='https://example.awsapps.com/start'
export aws_sso_region='eu-west-1'
export aws_sso_account_id='123456'
export aws_sso_role_name='AdministratorAccess'
export AWS_PROFILE="$aws_sso_session-$aws_sso_account_id-$aws_sso_role_name"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION
# configure the ~/.aws/config file.
# NB unfortunately, I did not find a way to create the [sso-session] section
#    inside the ~/.aws/config file using the aws cli. so, instead, manage that
#    file using python.
python3 <<'PY_EOF'
import configparser
import os
aws_sso_session = os.getenv('aws_sso_session')
aws_sso_start_url = os.getenv('aws_sso_start_url')
aws_sso_region = os.getenv('aws_sso_region')
aws_sso_account_id = os.getenv('aws_sso_account_id')
aws_sso_role_name = os.getenv('aws_sso_role_name')
aws_profile = os.getenv('AWS_PROFILE')
config = configparser.ConfigParser()
aws_config_directory_path = os.path.expanduser('~/.aws')
aws_config_path = os.path.join(aws_config_directory_path, 'config')
if os.path.exists(aws_config_path):
  config.read(aws_config_path)
config[f'sso-session {aws_sso_session}'] = {
  'sso_start_url': aws_sso_start_url,
  'sso_region': aws_sso_region,
  'sso_registration_scopes': 'sso:account:access',
}
config[f'profile {aws_profile}'] = {
  'sso_session': aws_sso_session,
  'sso_account_id': aws_sso_account_id,
  'sso_role_name': aws_sso_role_name,
  'region': aws_sso_region,
}
os.makedirs(aws_config_directory_path, mode=0o700, exist_ok=True)
with open(aws_config_path, 'w') as f:
  config.write(f)
PY_EOF
unset aws_sso_start_url
unset aws_sso_region
unset aws_sso_session
unset aws_sso_account_id
unset aws_sso_role_name
# show the user, user amazon resource name (arn), and the account id, of the
# profile set in the AWS_PROFILE environment variable.
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  aws sso login
fi
aws sts get-caller-identity
EOF
```

Or, set the AWS Account credentials using an Access Key, e.g.:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
cat >secrets.sh <<'EOF'
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
unset AWS_PROFILE
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
EOF
```

Review `main.tf`.

Load the secrets into the current shell session:

```bash
source secrets.sh
```

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
rm -f terraform.log
make terraform-apply
```

Show the terraform state:

```bash
make terraform-show
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `provision-app.sh` script to launch the example application.

After VM initialization is done (check the instance system log for cloud-init entries), test the `app` endpoint:

```bash
while ! wget -qO- "http://$(terraform output --raw app_ip_address)/test"; do sleep 3; done
```

Get the instance ssh host public keys, convert them to the knowns hosts format,
and show their fingerprints:

```bash
./aws-ssm-get-sshd-public-keys.sh \
  "$(terraform output --raw app_instance_id)" \
  | tail -1 \
  | jq -r .sshd_public_keys \
  | sed "s/^/$(terraform output --raw app_instance_id),$(terraform output --raw app_ip_address) /" \
  > app-ssh-known-hosts.txt
ssh-keygen -l -f app-ssh-known-hosts.txt
```

Using your ssh client, open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=app-ssh-known-hosts.txt \
  "ubuntu@$(terraform output --raw app_ip_address)"
cloud-init status --long --wait
tail /var/log/cloud-init-output.log
cat /etc/machine-id
id
df -h
wget -qO- localhost/try
systemctl status app
journalctl -u app
sudo iptables-save
sudo ip6tables-save
sudo ec2metadata
systemctl status snap.amazon-ssm-agent.amazon-ssm-agent
journalctl -u snap.amazon-ssm-agent.amazon-ssm-agent
sudo ssm-cli get-instance-information
sudo ssm-cli get-diagnostics
# list all the aws endpoints that the ssm agent uses.
sudo ssm-cli get-diagnostics \
  | perl -nle 'print $1 if /([a-z0-9.-]+\.amazonaws\.com)/i' \
  | sort -u \
  | while read endpoint; do
      dig +short a "$endpoint" | sort | while read ip; do
        echo "$endpoint: $ip"
      done
    done
exit
```

Using your ssh client, and [aws ssm session manager to proxy the ssh connection](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html), open a shell inside the VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=app-ssh-known-hosts.txt \
  -o ProxyCommand='aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p' \
  "ubuntu@$(terraform output --raw app_instance_id)"
ps -efww --forest
sudo ps -efww --forest
exit
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `sh` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a sh shell. to switch to a different one,
#    see the next example.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell.
#    NB that document is created in our account when session manager is used
#       for the first time.
# see https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-default-session-document.html
# see aws ssm describe-document --name SSM-SessionManagerRunShell
aws ssm start-session --target "$(terraform output --raw app_instance_id)"
echo $SHELL
id
sudo id
ps -efww --forest
sudo ps -efww --forest
exit
```

Using [aws ssm session manager](https://docs.aws.amazon.com/cli/latest/reference/ssm/start-session.html), open a `bash` shell inside the VM and execute some commands:

```bash
# NB this executes the command inside a sh shell, but we immediately switch to
#    the bash shell.
# NB the default ssm session --document-name is SSM-SessionManagerRunShell which
#    is created in our account when session manager is used the first time.
# see aws ssm describe-document --name AWS-StartInteractiveCommand --query 'Document.Parameters[*]'
# see aws ssm describe-document --name AWS-StartNonInteractiveCommand --query 'Document.Parameters[*]'
aws ssm start-session \
  --document-name AWS-StartInteractiveCommand \
  --parameters '{"command":["exec env SHELL=$(which bash) bash -il"]}' \
  --target "$(terraform output --raw app_instance_id)"
echo $SHELL
id
sudo id
ps -efww --forest
sudo ps -efww --forest
exit
```

Destroy the example:

```bash
make terraform-destroy
```

# References

* [Environment variables to configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
* [Token provider configuration with automatic authentication refresh for AWS IAM Identity Center](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) (SSO)
* [Managing access keys (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
* [AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
  * [Amazon Resource Names (ARNs)](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html)
* [Connect to the internet using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html#vpc-igw-internet-access)
* [Retrieve instance metadata](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
* [How Instance Metadata Service Version 2 works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html)
* [AWS Systems Manager (aka Amazon EC2 Simple Systems Manager (SSM))](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html)
  * [Amazon SSM Agent Source Code Repository](https://github.com/aws/amazon-ssm-agent)
  * [Amazon SSM Session Manager Plugin Source Code Repository](https://github.com/aws/session-manager-plugin)
  * [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
    * [Start a session](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)
      * [Starting a session (AWS CLI)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-cli)
      * [Starting a session (SSH)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-ssh)
        * [Allow and control permissions for SSH connections through Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html)
      * [Starting a session (port forwarding)](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-port-forwarding)

# Alternatives

* https://github.com/terraform-aws-modules
