#-------------------------------------------------------------------------------------------------------------------------------------
# VERSION REQUIREMENTS 
# Versions of Teraform and its providers pinned for stability
#-------------------------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = "~> 1.1.0"
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 3.20"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3"
    }
  }
}



data "aws_caller_identity" "current" {}
data "okta_groups" "okta_groups" {}

locals {
  groups    = [for group in data.okta_groups.okta_groups.groups : group if(length(regexall("(?i)${var.app}", element(split("-", group.name), 1))) > 0)]
  accounts  = [for group in local.groups : merge(group, { "account" = element(split("-", group.name), 2) }) if data.aws_caller_identity.current.account_id == element(split("-", group.name), 2)]
  group_map = [for group in local.accounts : merge(group, { "perms" = element(split("-", group.name), 3), "account" = "aws" })]


  app_settings_json = {  
  # AppFilter set by variable in variables.tf to restrict source of users
  "appFilter" : "${var.aws_saml_app_filter}",
  "awsEnvironmentType" : "aws.amazon",
    # Regex responsponsible for detecting group is meant to go to aws, with account ID, and mapped to the proper role
    "groupFilter" : "^app\\-aws\\-(?{{accountid}}\\d+)\\-(?{{role}}[\\w\\-]+)$"
    "joinAllRoles" : true,
    "loginURL" : "https://console.aws.amazon.com/ec2/home",
    "roleValuePattern" : "arn:aws:iam::$${accountid}:saml-provider/${var.aws_saml_provider_name},arn:aws:iam::$${accountid}:role/$${role}",
    "sessionDuration" : 3600,
    # Use Group Mapping will make the above regex work, so groups are automatically assigned to Role at specified account
    "useGroupMapping" : true,
    "identityProviderArn" : "aws_iam_saml_provider.${var.aws_saml_provider_name}.arn",
    }
}



data "aws_iam_policy" "valid_policies" {
  for_each = toset([ for group in local.group_map : group.perms ])
  name     = each.value
}



resource "aws_iam_saml_provider" "saml_provider" {
  for_each               = toset([ for account in local.accounts : account.account ])
  name                   = var.aws_saml_provider_name
  saml_metadata_document = join("", [ for metadata in module.saml-app.saml-metadata : metadata.metadata  ])
  tags = {
    "Name" = "okta sso saml provider"
  }
}

data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRoleWithSAML"]

    principals {
      type        = "Federated"
      identifiers = [for provider in aws_iam_saml_provider.saml_provider : provider.arn ]
    }

    condition {
      test     = "StringEquals"
      variable = "SAML:aud"

      values = [
        "https://signin.aws.amazon.com/saml"
      ]
    }
  }
}



#-------------------------------------------------------------------------------------------------------------------------------------
# ROLE CREATION
# The automatic group to role matching is great, but wanted a way to also generate the role and mape it to a  policy so this wouldn't
# have to be managed in AWS. The Group mapping maps User to Role, but with this, we'll automatically generate the role name as well
# The Role will have the same name as the Policy it maps to.  If no policy exists, it will fail, you can use either an AWS Managed
# Policy, or a custom one (can specify the custom policy in aws-policies terraform module)
#-------------------------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role" "okta-role" {
  for_each            = { for policy in data.aws_iam_policy.valid_policies : policy.name => policy }
  name                = each.value.name
  assume_role_policy  = data.aws_iam_policy_document.instance-assume-role-policy.json
  managed_policy_arns = [each.value.arn]
  tags = {
    "Name" = each.value.name
  }
}

module "saml-app" {
  source            = "../../../modules/accounts/saml-app/"
  app               = var.app
  okta-appname      = var.okta-appname
  groups            = local.group_map
  accounts          = [ for group in local.group_map : group.account ]
  app_links_json    = var.app_links_json
  app_settings_json = local.app_settings_json
}
