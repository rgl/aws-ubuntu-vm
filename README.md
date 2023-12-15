# About

An example aws ec2 ubuntu virtual machine.

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Set the account:

```bash
# set the account credentials.
# NB get these from your aws account iam console.
#    see Managing access keys (console) at
#        https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey
export AWS_ACCESS_KEY_ID='TODO'
export AWS_SECRET_ACCESS_KEY='TODO'
# set the default region.
export AWS_DEFAULT_REGION='eu-west-1'
# show the user, user amazon resource name (arn), and the account id.
aws sts get-caller-identity
```

Review `main.tf`.

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
make terraform-apply
```

Show the terraform state:

```bash
make terraform-show
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `provision-app.sh` script to launch the example application.

After VM initialization is done (check the instance system log for cloud-init entries), test the `app` endpoint:

```bash
wget -qO- "http://$(terraform output --raw app_ip_address)/test"
```

And open a shell inside the VM:

```bash
ssh "ubuntu@$(terraform output --raw app_ip_address)"
cloud-init status --wait
tail /var/log/cloud-init-output.log
exit
```

Destroy the example:

```bash
make terraform-destroy
```

# References

* [Environment variables to configure the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html)
* [Managing access keys (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html#Using_CreateAccessKey)
* [AWS General Reference](https://docs.aws.amazon.com/general/latest/gr/Welcome.html)
  * [Amazon Resource Names (ARNs)](https://docs.aws.amazon.com/general/latest/gr/aws-arns-and-namespaces.html)
* [Connect to the internet using an internet gateway](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html#vpc-igw-internet-access)

# Alternatives

* https://github.com/terraform-aws-modules
