# week_5_IaC

### This repository contains Terraform files to configure Azure environment with:
1. One vnet.
2. Two subnets- one public and one private.
3. VM linux scale set, with auto-scaling setting (with one server right now for cost effective), with weight tracker application on it.
4. Public load balancer that speaks with the scale set.
5. Postgres VM that speaks only to the scale set.

It was a really hard challenge!!

Thanks!
