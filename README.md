# Tethys - Zero-Trust Ephemeral Secure File Drop

Tethys is a microservices platform for the highly secure, *temporary* transfer
of sensitive files. Data is encrypted client-side before it ever touches the
network, assigned a strict TTL or single-use constraint, and cryptographically
wiped from object storage the moment that constraint is met. The stack is
deployed on AWS via a fully automated DevSecOps pipeline.

> Named after Tethys, the Greek titan of fresh, ephemeral water: the files flow
> through and leave no trace.

## At a glance

```text
  Browser  ->  AWS ALB  ->  Nginx Ingress  ->  Frontend (React, WebCrypto)
                                            ->  Vault    (Go, REST)
                                                     |
                              Wiper CronJob (Go)  ---+
                                                     v
                                     RDS Postgres + S3 (encrypted)
```

- **Frontend** encrypts the file in the browser with AES-256-GCM derived from a
  user passphrase (PBKDF2, 300k iters). Plaintext never leaves the client.
- **Vault** mints single-use, short-lived presigned S3 URLs and stores only
  metadata (id, sha256, size, TTL, remaining_downloads) in Postgres.
- **Wiper** runs every 5 minutes as a Kubernetes `CronJob` and hard-deletes
  objects whose TTL has expired or whose download budget is exhausted.
- **Infra** is Terraform on AWS: VPC, 3-5 `t3.micro` EC2 instances, RDS
  Postgres `db.t3.micro`, S3 with SSE + lifecycle backstop, ALB + ACM, scoped
  IAM roles per workload.
- **K3s** gives us real, certified Kubernetes on Free-Tier EC2 (EKS is not
  Free Tier; Minikube is explicitly disallowed by the spec).
- **CI/CD** is Jenkins LTS: lint -> SAST (`gosec`, `semgrep`, `trivy`) -> test
  -> build -> image scan -> ECR push -> `terraform plan` -> `kubectl apply`.

See [`docs/architecture.md`](docs/architecture.md) for the full NIST SP 800-207
zero-trust mapping and threat model.

## Repo layout

```text
.
├── docs/                Architecture, AWS bootstrap, runbook, diagrams
├── infra/
│   ├── terraform/       AWS (VPC, EC2, RDS, S3, IAM, ALB)
│   └── ansible/         OS hardening, K3s, Jenkins
├── services/
│   ├── vault/           Go REST API
│   ├── wiper/           Go CronJob binary
│   └── frontend/        React + Vite + TypeScript
├── deploy/k8s/          Namespace, deployments, services, NetworkPolicies,
│                        Ingress, Wiper CronJob
└── ci/
    ├── Jenkinsfile      Pipeline definition
    └── jenkins/casc.yaml Jenkins Configuration-as-Code
```

## Quickstart

```bash
# 1. One-time AWS bootstrap (IAM user, access keys, MFA).
open docs/aws-bootstrap.md                   # follow every step

# 2. Pick your inputs.
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars # edit key_pair_name, db_password, allowed_ssh_cidr

# 3. Provision AWS.
terraform init
terraform apply                              # ~8-10 minutes

# 4. Configure the instances (K3s cluster + Jenkins).
cd ../ansible
ansible-playbook -i inventory.ini playbooks/site.yml

# 5. Deploy the app via Jenkins (open the URL from `terraform output jenkins_url`
#    and run the `tethys` pipeline), or manually:
cd ../../deploy/k8s
kubectl apply -f .

# 6. Grab the public URL.
cd ../../infra/terraform
terraform output alb_dns_name
```

A convenience `Makefile` wraps the common commands - `make plan`, `make apply`,
`make deploy`, `make destroy`, `make stop-ec2` (cost-saver).

## Local development (no AWS required)

```bash
# Vault + Postgres + MinIO via docker-compose
cd services/vault && make dev            # starts the stack on http://localhost:8080

# Frontend
cd services/frontend && npm install && npm run dev
```

The frontend talks to `http://localhost:8080` by default; override with
`VITE_API_BASE_URL`.

## Security posture (summary)

- **Identity**: every workload has its own IAM role with the minimum S3
  verbs it needs (`vault`: `PutObject`/`GetObject`; `wiper`: `DeleteObject`/
  `ListBucket`). Jenkins cannot read user files. Vault cannot delete them.
- **Data**: plaintext lives only in the browser. S3 is SSE-encrypted and has
  a 7-day lifecycle rule as a backstop to the Wiper. TLS terminates at the
  ALB and is re-established in-cluster by Nginx Ingress.
- **Network**: Kubernetes NetworkPolicies deny-by-default; only the edges
  declared in `deploy/k8s/policies/` are allowed. RDS lives in a subnet with
  no route to an internet gateway.
- **Supply chain**: every image is built by Jenkins from pinned base digests,
  scanned with Trivy, and signed-then-deployed. No prebuilt public images in
  the cluster apart from `nginx:alpine-slim` and distroless.

Full mapping to NIST SP 800-207 in [`docs/architecture.md`](docs/architecture.md).

## FAQ

**Why K3s and not EKS?** EKS has a $0.10/hr control plane fee. K3s is fully
certified Kubernetes that runs comfortably on a `t3.micro` and has no
per-cluster fee. The spec also explicitly bans Minikube-style local clusters.

**Why public-subnet EC2 instead of private + NAT?** A single NAT Gateway
costs ~$32/month, which blows the free-tier budget. The instances are
protected by tight security groups (SSH only from your IP, app ports only
from the ALB), so public subnet is acceptable for a demo. Move them private
+ NAT or VPC endpoints for production.

**Can I use a real domain?** Yes. Point a Route 53 ALIAS record at
`alb_dns_name`, request an ACM cert in `us-east-1`, set
`acm_certificate_arn` in `terraform.tfvars`, and re-apply.

## Tear down

```bash
cd infra/terraform
terraform destroy
```

If destroy complains that the S3 bucket is not empty, run
`aws s3 rm s3://<bucket> --recursive` first.
