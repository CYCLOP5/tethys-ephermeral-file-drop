# AWS Bootstrap Guide

Follow this guide **once**, before you run any Terraform, Ansible, or Jenkins
step in the Tethys project. Its job is to get you a set of *programmatic* AWS
credentials that can provision the stack, while keeping your account safe.

> The rest of the repo (Terraform, Ansible, Jenkins, `kubectl`) assumes these
> steps are done. If `aws sts get-caller-identity` does not work, nothing
> else will.

---

## 0. Lock down the console account first

If at any point you pasted your AWS **console** username or password in chat,
screenshots, Git, or a ticket, treat them as compromised and do this now:

1. Sign in to the AWS console as the affected user.
2. Top-right -> username -> **Security credentials**.
3. Under **Console password**, click **Update**. Pick a strong, unique password
   stored in a password manager.
4. Under **Multi-factor authentication (MFA)**, click **Assign MFA device** and
   register a virtual MFA app (1Password, Authy, Google Authenticator).
5. While you are there, scroll to **Access keys** and delete any key you do not
   recognise.
6. Open **CloudTrail -> Event history** and skim the last 24 h for unknown
   `ConsoleLogin`, `CreateUser`, `CreateAccessKey`, `RunInstances`,
   `PutObject`, or anything else you did not do. If you see something, rotate
   everything and contact AWS support.

Do the same for the root account (and enable MFA on it if you have not already).
Then sign out of root and stop using it.

---

## 1. Create a deployer IAM user

We want a dedicated, non-human-looking identity to run Terraform/Ansible. Never
reuse your personal console login for this.

1. Console -> **IAM** -> **Users** -> **Create user**.
2. Name: `tethys-deployer`. Leave "Provide user access to the AWS Management
   Console" **unchecked**. This is an API-only user.
3. **Next**. On the permissions page choose **Attach policies directly** and
   attach `AdministratorAccess`. We will scope this down in a later hardening
   pass (see `docs/runbook.md`), but for day-1 bring-up an admin policy keeps
   you from fighting IAM instead of shipping.
4. **Next** -> **Create user**.

## 2. Mint an access key

1. Click the new `tethys-deployer` user -> **Security credentials** tab.
2. Scroll to **Access keys** -> **Create access key**.
3. Use case: **Command Line Interface (CLI)**. Tick the confirmation box.
4. Description tag: `tethys-terraform`.
5. **Create access key**.
6. **Download .csv file**. The secret access key is shown exactly once - if
   you close this page without downloading, you have to rotate and start over.

Keep the CSV somewhere your password manager can see but Git cannot.

## 3. Configure the AWS CLI

On your workstation (macOS/Linux):

```bash
aws --version          # must be >= 2.13
aws configure --profile tethys
# AWS Access Key ID:     <paste from csv>
# AWS Secret Access Key: <paste from csv>
# Default region name:   us-east-1
# Default output format: json
```

This writes to `~/.aws/credentials` and `~/.aws/config` under a `[tethys]`
profile. **Do not commit these files.**

Tell every tool in this repo to use that profile:

```bash
export AWS_PROFILE=tethys
export AWS_REGION=us-east-1
```

You will want these two lines in your shell rc (`~/.zshrc`, `~/.bashrc`) or in
a `direnv` `.envrc` at the repo root.

## 4. Smoke test

```bash
aws sts get-caller-identity
```

Expected output:

```json
{
  "UserId":  "AIDA...............",
  "Account": "465532803709",
  "Arn":     "arn:aws:iam::465532803709:user/tethys-deployer"
}
```

If you see your own user name instead of `tethys-deployer`, the profile is not
active - re-export `AWS_PROFILE=tethys`.

## 5. Free Tier sanity check

Before you run `terraform apply`, open the **Billing** dashboard:

1. **Billing and Cost Management** -> **Free Tier**. Confirm you still have
   hours left on EC2 (`t2.micro`/`t3.micro`) and RDS (`db.t3.micro`).
2. **Billing preferences** -> enable **Receive AWS Free Tier alerts** and set
   your email.
3. **Budgets** -> create a **Zero-spend budget** (action = email you when
   forecasted charges > $0.01). This is the single most useful thing you can
   do to avoid a surprise bill.

### What this project spends

Assuming `var.k3s_agent_count = 1` and you `stop` instances when not demoing:

| Service        | Resource                              | Free Tier?                                  |
| -------------- | ------------------------------------- | ------------------------------------------- |
| EC2            | 3 x `t3.micro` (jenkins, k3s-server, 1 agent) | 750 hrs/mo shared - fine if stopped overnight |
| RDS            | `db.t3.micro` Postgres, 20 GB gp3     | 750 hrs/mo, 20 GB - yes, free               |
| S3             | One bucket, < 5 GB demo traffic       | Yes                                         |
| ALB            | 1 application load balancer           | 750 hrs/mo new-account free tier            |
| EBS            | 3 x 8 GB gp3 root volumes             | 30 GB total free tier                       |
| Data transfer  | < 100 GB/month out                    | 100 GB/mo free                              |
| NAT Gateway    | **NOT USED**                          | (would be ~$32/mo, so we avoid it)          |
| EKS            | **NOT USED**                          | (~$72/mo control plane, so we self-host K3s) |

Running all 3 EC2 instances 24x7 = ~2,160 hrs/mo > 750 hrs, so you will pay for
~1,400 micro-hours (~ $15). Either stop instances after each demo or use the
`./scripts/stop-all.sh` helper (see `docs/runbook.md`).

## 6. What to hand Terraform

`infra/terraform/terraform.tfvars.example` lists every variable. Copy it to
`terraform.tfvars` (git-ignored) and fill in:

- `aws_region` - match `AWS_REGION`
- `key_pair_name` - the name of an EC2 key pair you control. Create one with:
  ```bash
  aws ec2 create-key-pair --key-name tethys \
      --query 'KeyMaterial' --output text > ~/.ssh/tethys.pem
  chmod 400 ~/.ssh/tethys.pem
  ```
- `db_password` - random string. Generate:
  ```bash
  openssl rand -base64 24
  ```
- `allowed_ssh_cidr` - your home IP as `<ip>/32`. Find it with
  `curl -s https://checkip.amazonaws.com`/32.
- `acm_certificate_arn` - leave empty for now; the ALB will listen on :80 only
  until you supply one.

Now you can run:

```bash
cd infra/terraform
terraform init
terraform plan
```

If `plan` renders a tree of resources without errors, the bootstrap is done
and you can move on to the main README.

---

## Rotating the deployer key later

Every ~90 days, or immediately if you think a key has leaked:

```bash
aws iam create-access-key --user-name tethys-deployer            # new key
aws configure --profile tethys                                   # paste new
aws sts get-caller-identity                                      # verify
aws iam delete-access-key --user-name tethys-deployer \
    --access-key-id <OLD_KEY_ID>                                 # retire old
```

## Tearing the account back down

When you are done demoing:

```bash
cd infra/terraform && terraform destroy
aws iam delete-access-key --user-name tethys-deployer --access-key-id <...>
aws iam detach-user-policy --user-name tethys-deployer \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-user --user-name tethys-deployer
```

If `terraform destroy` fails on the S3 bucket because it still has objects,
empty it first:

```bash
aws s3 rm s3://<bucket> --recursive
```

---

You are now ready to provision Tethys. Head back to the top-level
[`README.md`](../README.md).
