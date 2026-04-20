# Tethys Runbook

Day-2 operations, tuned for a small self-managed K3s cluster on AWS Free Tier.

---

## Quick references

| Task                     | Command / URL |
| ------------------------ | ------------- |
| Jenkins UI               | `terraform -chdir=infra/terraform output jenkins_url` |
| ALB public URL           | `terraform -chdir=infra/terraform output alb_dns_name` |
| Kubeconfig               | `scp ec2-user@<k3s-server>:/etc/rancher/k3s/k3s.yaml ~/.kube/tethys` (replace `127.0.0.1` with the server's private IP) |
| Tail Vault logs          | `kubectl -n tethys logs -l app.kubernetes.io/name=vault -f` |
| Trigger Wiper now        | `kubectl -n tethys create job --from=cronjob/wiper manual-wipe-$(date +%s)` |

---

## Rotating secrets

### Database password

1. Update `db_password` in `infra/terraform/terraform.tfvars`.
2. `terraform apply` - the RDS instance updates its master password in place.
3. Update the `DATABASE_URL` value in `deploy/k8s/vault/secrets.yaml` (or the
   SSM parameter, if you're using Jenkins to inject secrets).
4. `kubectl -n tethys rollout restart deploy/vault`.

### JWT signing key

1. Generate a new secret: `openssl rand -base64 48`.
2. Patch the Secret: `kubectl -n tethys edit secret vault-secrets`, set
   `JWT_SECRET`.
3. `kubectl -n tethys rollout restart deploy/vault`.
4. Old tokens are immediately invalid; re-issue.

### Deployer access key

See [`docs/aws-bootstrap.md` - Rotating the deployer key later](./aws-bootstrap.md#rotating-the-deployer-key-later).

---

## Revoking a share link

If a link has been leaked and should not be downloadable again:

```bash
psql "$DATABASE_URL" -c \
  "UPDATE files SET remaining_downloads = 0, expires_at = now() WHERE download_token = '<token>';"
```

The Wiper CronJob will pick it up and purge the S3 object on its next run.
Force a run immediately with:

```bash
kubectl -n tethys create job --from=cronjob/wiper manual-revoke-$(date +%s)
```

---

## Evacuating a K3s agent

```bash
kubectl cordon   <node>
kubectl drain    <node> --ignore-daemonsets --delete-emptydir-data
# then reboot / replace the EC2 instance
kubectl uncordon <node>
```

If the agent is being replaced permanently, also delete the Node:

```bash
kubectl delete node <node>
```

---

## Scaling up

Edit `infra/terraform/terraform.tfvars`:

```hcl
k3s_agent_count = 3
```

Then `terraform apply && ansible-playbook -i inventory.ini playbooks/site.yml`.
The new agent will auto-join the cluster; nothing else to do.

Warning: more than 1 `t3.micro` agent running 24x7 will exceed 750-hour Free
Tier. Stop them when not demoing (`make stop-ec2`).

---

## Backups

RDS is configured with `backup_retention_period = 1` day. For real use, set
this to >= 7 and consider enabling automated snapshots plus cross-region
copy:

```hcl
# infra/terraform/rds.tf
backup_retention_period = 7
copy_tags_to_snapshot    = true
```

The S3 bucket has versioning enabled; objects deleted by the Wiper are
immediately tombstoned, and the noncurrent-version rule cleans them after
1 day. You can recover an object within that window:

```bash
aws s3api list-object-versions --bucket <bucket> --prefix files/<id>
aws s3api copy-object --bucket <bucket> --key files/<id> \
  --copy-source <bucket>/files/<id>?versionId=<vid>
```

---

## Common failure modes

### `ImagePullBackOff` on pods

- ECR lifecycle may have expired the tag. Re-run the pipeline.
- Node IAM role is missing `ecr:GetAuthorizationToken`. `iam.tf` already
  grants this via `aws_iam_role.k3s_agent`; verify with
  `aws iam list-attached-role-policies --role-name tethys-dev-k3s-agent`.

### `CrashLoopBackOff` on Vault

- Check `kubectl -n tethys logs deploy/vault --previous`.
- 90% of the time it's a bad `DATABASE_URL` (wrong password, missing
  `sslmode=require`, or the security group is blocking port 5432).

### Wiper never deletes anything

- Verify the pod's IAM role allows `s3:DeleteObject` on the bucket/prefix:
  `aws iam get-role-policy --role-name tethys-dev-wiper --policy-name tethys-dev-wiper`
- Tail the pod: `kubectl -n tethys logs -l app.kubernetes.io/name=wiper --tail=200`.
- Verify there's actually something to wipe:
  `psql "$DATABASE_URL" -c "SELECT count(*) FROM files WHERE expires_at <= now() OR remaining_downloads <= 0;"`.

### ALB health checks failing

- The target group health checks `/healthz` on port 30080 (Nginx Ingress
  NodePort). Ensure the Ingress controller is actually listening on 30080:
  `kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml`.
- The `k3s_agent` security group must allow `30000-32767/tcp` from the ALB
  security group - `security-groups.tf` already does this.

---

## Cost guardrails

- `make stop-ec2` stops every Tethys EC2 instance. `make start-ec2` brings
  them back.
- Set an AWS Budgets zero-spend alert (see `docs/aws-bootstrap.md`).
- The S3 lifecycle rule ensures orphaned objects disappear within 7 days
  even if the Wiper is offline for that long.
- `terraform destroy` followed by `aws iam delete-user` fully unwinds the
  project.

---

## Tightening IAM after day 1

The deployer IAM user starts with `AdministratorAccess` to make bring-up
frictionless. Once the stack is stable, replace that policy with a scoped
version. A minimum that works for `terraform plan/apply`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["ec2:*","vpc:*","elasticloadbalancing:*","s3:*","rds:*","iam:*","ecr:*","ssm:*","kms:Describe*","kms:List*"], "Resource": "*" }
  ]
}
```

Then iterate the deny list based on CloudTrail's `ReadOnly/ReadWrite`
events for the user.

---

## Incident playbook (summary)

1. **Contain**: `make stop-ec2` to freeze compute. Rotate any credentials
   that might be compromised.
2. **Evidence**: snapshot the RDS instance, export the S3 bucket inventory,
   pull CloudTrail events for the last 24 hours to a safe bucket.
3. **Eradicate**: `terraform destroy` is nuclear but reliable. Rebuild from
   known-good state by running `terraform apply` on a clean checkout.
4. **Recover**: restore RDS from the snapshot into the new stack, re-apply
   the manifests, re-issue JWT secrets.
5. **Post-mortem**: write it up in `docs/`, link to CloudTrail event IDs.
