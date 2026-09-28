# EC2-ASG-ALB-Terraform

A minimal, from-scratch Terraform stack that deploys a **highly available web tier** on AWS: a VPC spread across multiple Availability Zones, an Auto Scaling Group of EC2 instances in private subnets, and an internet-facing Application Load Balancer in public subnets. No third-party modules — every resource is written out so the architecture is easy to read and reason about.

```
                                     Internet
                                        │
                                        ▼
┌─────────────────────────── ALB (public subnets, spans all AZs) ───────────────────────────┐
│                                                                                           │
└───────────────────────────────────────┬───────────────────────────────────────────────────┘
                                        │ :80 → Target Group
                     ┌──────────────────┴──────────────────────┐
                     ▼                                         ▼
        ┌─────────────────────────┐               ┌─────────────────────────┐
        │  Private subnet (AZ-a)  │               │  Private subnet (AZ-b)  │
        │   EC2 (nginx, :80)      │               │   EC2 (nginx, :80)      │
        └────────────┬────────────┘               └────────────┬────────────┘
                     │ outbound only                           │ outbound only
                     ▼                                         ▼
              NAT Gateway (AZ-a, or one per AZ)  ◄─────────────┘
                     │
                     ▼
              Internet Gateway → Internet
```

The Auto Scaling Group owns both EC2 instances above — this is the group's actual desired capacity spread across AZs, not two independent servers.

---

## Table of contents

- [Repo layout](#repo-layout)
- [Prerequisites](#prerequisites)
- [Quick start](#quick-start)
- [How the network is built](#how-the-network-is-built)
- [How the ALB, target group, and ASG span multiple AZs](#how-the-alb-target-group-and-asg-span-multiple-azs)
- [Request lifecycle, end to end](#request-lifecycle-end-to-end)
- [Security model](#security-model)
- [Scaling and health checks](#scaling-and-health-checks)
- [Variables reference](#variables-reference)
- [Outputs](#outputs)
- [Validating the deployment](#validating-the-deployment)
- [What happens when you change things](#what-happens-when-you-change-things)
- [Cleaning up](#cleaning-up)
- [Known limitations](#known-limitations)

---

## Repo layout

Everything lives in one flat root module under `Terraform/` — no submodules yet, but variables are already written so this can be lifted into a module later without renaming anything.

| File | Contains |
|---|---|
| `versions.tf` | Terraform and AWS provider version constraints, commented-out S3 backend |
| `providers.tf` | AWS provider config, `default_tags` |
| `variables.tf` | Every input variable (the eventual module interface) |
| `data.tf` | `aws_availability_zones` data source |
| `locals.tf` | Derived values: AZ list, AZ→index map, NAT AZ selection |
| `vpc.tf` | VPC, Internet Gateway, subnets, route tables, NAT Gateway(s) |
| `sg.tf` | ALB security group, app security group, and their rules |
| `iam.tf` | IAM role + instance profile for SSM (no SSH, no key pair) |
| `launch_template.tf` | EC2 launch template (AMI, instance type, user data, IMDSv2) |
| `asg.tf` | Auto Scaling Group + CPU target-tracking scaling policy |
| `alb.tf` | Application Load Balancer, target group, HTTP listener |
| `outputs.tf` | ALB DNS name, subnet IDs, NAT IPs, ASG name |
| `user_data.sh.tpl` | Boot script — installs nginx, serves a page with instance ID + AZ |

## Prerequisites

- Terraform `>= 1.6`
- AWS provider `>= 5.40, < 7.0`
- An AWS account and credentials available to the provider (env vars, `~/.aws/credentials`, or an SSO profile)
- `aws` CLI (for validation steps and SSM sessions later)

## Quick start

```bash
cd Terraform
cp terraform.tfvars.example terraform.tfvars   # adjust values if needed
terraform init
terraform validate
terraform plan
terraform apply
```

When `apply` finishes:

```bash
terraform output app_url
curl "$(terraform output -raw app_url)"
```

Refresh a few times — the returned instance ID and Availability Zone will change as the ALB spreads requests across targets.

---

## How the network is built

**VPC.** One VPC (`10.0.0.0/16` by default) holds everything.

**AZ selection.** `data.aws_availability_zones.available` (in `data.tf`) asks AWS which AZs exist in the region. `locals.tf` then takes the first `var.az_count` of them:

```hcl
azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
az_index = { for i, az in local.azs : az => i }
```

`az_index` maps each AZ name to a number (`ap-south-1a → 0`, `ap-south-1b → 1`, …). That number is what drives every subnet's CIDR block below, and it's why AZs are looked up dynamically instead of hardcoded — the same config works in any region.

**Subnets, keyed by AZ.** Both subnet resources use `for_each = local.az_index` instead of `count`. This one choice is what makes the network resize safely:

```hcl
resource "aws_subnet" "public" {
  for_each   = local.az_index
  cidr_block = cidrsubnet(var.vpc_cidr, var.subnet_newbits, each.value)
  ...
}

resource "aws_subnet" "private" {
  for_each   = local.az_index
  cidr_block = cidrsubnet(var.vpc_cidr, var.subnet_newbits, each.value + local.private_offset)
  ...
}
```

With `count`, subnets are indexed `0, 1, 2…` by position — removing the first one shifts every index down and Terraform destroys and recreates all of them. With `for_each` keyed by AZ **name**, each subnet's identity is tied to its AZ, not its position in a list. Add a third AZ and Terraform creates exactly one new subnet pair; the existing two are untouched.

The `+ 100` offset (`private_offset`) on private subnets just keeps their CIDR math from overlapping with public subnets' — with `subnet_newbits = 8` you get `/24`s, so public subnets land at `10.0.0.0/24`, `10.0.1.0/24`… and private ones at `10.0.100.0/24`, `10.0.101.0/24`…

**Routing.**
- **Public**: one shared route table with a `0.0.0.0/0` route to the Internet Gateway, associated with every public subnet.
- **Private**: **one route table per AZ** (`for_each = local.az_index`), each with its own `0.0.0.0/0` route to a NAT Gateway. Per-AZ route tables matter for real HA — see the NAT section below.

**NAT Gateways.** Controlled by `single_nat_gateway`:

```hcl
nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs
```

- `true` (default, cheap): one NAT Gateway in the first AZ. **Every** private route table points at it — cheaper, but if that one AZ has an outage, private instances in the *other* AZ also lose internet egress even though their subnet is fine.
- `false` (real HA): one NAT Gateway per AZ, and each AZ's private route table points at its **own** NAT. An AZ failure only takes out egress for that AZ.

This is the one place in the repo where "highly available" is a genuine trade-off you choose, not a given — `single_nat_gateway = true` trades AZ-independent egress for cost.

---

## How the ALB, target group, and ASG span multiple AZs

This is the core of the "no downtime, no single point of failure" design, and it depends on three unrelated resources all being told about the same set of subnets.

**1. The ALB spans AZs via its `subnets` argument:**

```hcl
resource "aws_lb" "app" {
  subnets = [for s in aws_subnet.public : s.id]
  ...
}
```

An ALB isn't a single server — AWS provisions one **ALB node per subnet you give it**, each with its own IP, all behind one DNS name. Passing every public subnet means a node exists in every AZ. If one AZ goes down, the DNS name still resolves and the surviving node(s) keep serving traffic — clients never see a different endpoint, they just stop getting routed to the dead AZ's node.

**2. The target group is just a routing table — it doesn't span anything itself.** `aws_lb_target_group.app` has no subnet or AZ configuration at all. Its only job is to hold a list of registered targets (instance IDs + ports) and their health status. It becomes multi-AZ purely because of what gets registered into it — which is entirely the ASG's doing.

**3. The ASG spans AZs via `vpc_zone_identifier`, and registers into the target group via `target_group_arns`:**

```hcl
resource "aws_autoscaling_group" "app" {
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]
  target_group_arns   = [aws_lb_target_group.app.arn]
  ...
}
```

`vpc_zone_identifier` is the list of subnets the ASG is allowed to launch instances into — here, every private subnet, i.e. every AZ. The ASG's own internal logic (not anything in this repo) tries to balance instance count evenly across whichever AZs you give it. `target_group_arns` tells the ASG: "whenever you launch an instance, register it in this target group automatically; whenever you terminate one, deregister it automatically." No script, no Lambda, no manual step — it's a built-in ASG behavior.

**Put together:** the ALB has a node in every AZ (because of its `subnets`), and behind it the target group holds a live, self-updating list of instances that the ASG keeps spread across those same AZs (because of `vpc_zone_identifier`). Three independent resources, one shared list of AZs — that alignment is the entire HA story. If you only fixed the ALB's subnets and left the ASG in one AZ, you'd have a highly available load balancer pointing at a single point of failure.

---

## Request lifecycle, end to end

1. A client resolves the ALB's DNS name (`terraform output alb_dns_name`) — this can return any of the ALB's per-AZ IPs.
2. The request hits an ALB node on port 80 (`aws_lb_listener.http`).
3. The listener's `default_action` forwards it to `aws_lb_target_group.app`.
4. The target group picks a **healthy** registered target (an EC2 instance) — from any AZ, not necessarily the one the ALB node is in. ALB traffic naturally crosses AZs to reach targets.
5. The instance's nginx (installed by `user_data.sh.tpl`) answers on port 80 and returns a page showing its own instance ID and AZ — this is what lets you *see* the load balancing happen by refreshing.
6. The ALB checks `GET /health` on each target every 15 seconds (`health_check` block in `alb.tf`). Two consecutive successes mark a target healthy; three consecutive failures mark it unhealthy and traffic stops routing there — before the ASG even notices anything is wrong.

---

## Security model

Two security groups, wired so only the ALB can ever reach an instance (see `sg.tf`):

- **ALB SG** — ingress: TCP 80 from `0.0.0.0/0`. Egress: only to the app SG, on the app port.
- **App SG** — ingress: only from the ALB SG, on the app port. Egress: all traffic (needed for `dnf install`, SSM, and any AWS API calls), which exits via NAT.

The ingress/egress pair reference each other's **security group ID**, not a CIDR block. That means the rule keeps working no matter how many ALB nodes exist or what IPs they get — "from anything in the ALB SG" survives scaling in a way that "from 10.0.x.x" would not.

Instances have **no SSH access and no public IP.** `iam.tf` attaches `AmazonSSMManagedInstanceCore` to an instance role, so access for debugging is via `aws ssm start-session --target <instance-id>` instead of a key pair or bastion host. The launch template also enforces IMDSv2 (`http_tokens = "required"`), which blocks the SSRF-style credential theft that plain IMDSv1 is vulnerable to.

---

## Scaling and health checks

- **`health_check_type = "ELB"`** on the ASG (`asg.tf`) means the ASG trusts the ALB's health check, not just whether the EC2 instance is "running." An instance that's up but failing `/health` gets replaced.
- **Target tracking scaling** (`aws_autoscaling_policy.cpu`) keeps average CPU across the group near `var.cpu_target` (50% by default) — AWS adds or removes instances automatically to hold that line, no manual thresholds to tune.
- **`instance_refresh`** with `min_healthy_percentage = 100` / `max_healthy_percentage = 200` means that whenever the launch template changes (new AMI, new instance type, new user data), the ASG launches replacement instances *first* and only then terminates the old ones — capacity never dips below 100% during a rollout.
- **`ignore_changes = [desired_capacity]`** — once created, the scaling policy owns desired capacity. Terraform won't fight it by resetting the count back to `var.asg_desired_capacity` on every apply.

---

## Variables reference

| Variable | Default | Purpose |
|---|---|---|
| `project` | `ha-web` | Name prefix for every resource |
| `region` | `ap-south-1` | AWS region |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `az_count` | `2` | Number of AZs (2–6) to spread subnets across |
| `subnet_newbits` | `8` | Extra CIDR bits per subnet (`/16` + 8 = `/24`) |
| `single_nat_gateway` | `true` | One shared NAT vs. one per AZ |
| `app_port` | `80` | Port the app listens on, and the ALB forwards to |
| `health_check_path` | `/health` | ALB target group health check path |
| `instance_type` | `t3.micro` | EC2 instance type |
| `ami_ssm_parameter` | latest AL2023 | SSM parameter resolved at launch — no AMI ID drift |
| `asg_min_size` / `asg_max_size` | `2` / `6` | ASG size bounds |
| `asg_desired_capacity` | `2` | Initial size only — ignored after creation |
| `cpu_target` | `50` | Target average CPU % for scaling |
| `enable_deletion_protection` | `false` | ALB deletion protection |

## Outputs

| Output | Description |
|---|---|
| `alb_dns_name` / `app_url` | Where to reach the app |
| `vpc_id` | VPC ID |
| `public_subnet_ids` / `private_subnet_ids` | Map of AZ → subnet ID |
| `nat_public_ips` | NAT egress IP(s) — should match what a private instance sees as its own public IP |
| `asg_name` | Auto Scaling Group name |

---

## Validating the deployment

**See load spread across AZs:**
```bash
for i in $(seq 1 10); do curl -s "$(terraform output -raw app_url)"; echo; done
```

**Confirm an instance has no public access and reaches the internet only via NAT:**
```bash
aws ssm start-session --target <instance-id>
curl ifconfig.me   # should match one of the IPs in `terraform output nat_public_ips`
```

**Simulate an AZ failure:** terminate every instance in one AZ (or temporarily drop that AZ's subnet from `vpc_zone_identifier`) and confirm the ALB keeps serving from the other AZ with no failed requests, then watch the ASG relaunch capacity.

---

## What happens when you change things

- **Adding an AZ** (`az_count` 2 → 3): safe, no downtime. Existing subnets are untouched (`for_each` by AZ name); Terraform only adds the new pair, and the ASG/ALB pick it up because both reference `aws_subnet.public`/`private` by `for_each`, not a fixed list.
- **Removing an AZ:** safe for users, but subnet deletion can briefly fail with `DependencyViolation` while the ASG drains that AZ — a second `apply` a minute later clears it.
- **Changing the launch template** (instance type, user data): triggers the rolling `instance_refresh` — no capacity dip.
- **Changing `asg_min_size`/`asg_max_size`:** in place, no downtime.
- **Renaming the ASG, or changing `vpc_cidr`/`subnet_newbits`/AZ order:** forces replacement of the affected resources — this is destructive, plan carefully.

## Cleaning up

```bash
terraform destroy
```

The NAT Gateway(s) and ALB bill by the hour whether or not they're serving traffic — don't leave this running unattended.

## Known limitations

- HTTP only — no HTTPS listener yet (was intentionally removed; see the comment in `alb.tf` for how to add it back with an ACM certificate).
- Single flat root module — fine for learning/portfolio use, but would need splitting into `modules/network`, `modules/compute`, etc. for reuse across environments.
- Local Terraform state by default — the S3 backend block in `versions.tf` is commented out; enable it before using this in a team setting.