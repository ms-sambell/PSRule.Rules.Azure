---
severity: Important
pillar: Security
category: Infrastructure provisioning
resource: All resources
online version: https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.Deployment.AdminUsername/
---

# Avoid hardcoded user names

## SYNOPSIS

Avoid using hardcoded sensitive values such as user names in deployments.

## DESCRIPTION

When defining resource deployments, many values can be passed as literal values or parameters.
For any sensitive values, such as user names, it is recommended to use secure parameters.
Hardcoded literal strings can be broadly read by anyone with read access to the deployment or source code.

Exposing user names within deployments provides information that may assist a malicious actor to gain access to a system.

## RECOMMENDATION

Consider using secure parameters for all sensitive properties including user names, which are a component of a credential.

## LINKS

- [Pipeline secret management](https://docs.microsoft.com/azure/architecture/framework/security/deploy-infrastructure#pipeline-secret-management)
- [Security recommendations for parameters](https://docs.microsoft.com/azure/azure-resource-manager/templates/best-practices#security-recommendations-for-parameters)
