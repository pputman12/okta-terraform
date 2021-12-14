terraform {
  backend "s3" {
    key            = "staging/accounts/aws-iam/roles/terraform.tfstate"
  }
}

#terraform {
#  required_providers {
#    okta = {
#      source  = "okta/okta"
#      version = "~> 3.20"
#    }
#  }
#}


provider "aws" {
	region = "us-east-2"
}

data "terraform_remote_state" "okta_sso_arn" {
  backend = "s3"

  config = {
    bucket = "terraform-okta-backend-pputman"
    region = "us-east-2"
    key    = "staging/accounts/okta/aws-app/terraform.tfstate"
  }
}


data "aws_iam_policy_document" "instance-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRoleWithSAML"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.okta_sso_arn.outputs.okta_sso_arn] 
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


resource "aws_iam_role" "FullAccess" {
  name                = "FullAccess"
  assume_role_policy  = data.aws_iam_policy_document.instance-assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] 
}



resource "aws_iam_role" "S3Full" {
  name                = "S3Full"
  assume_role_policy  = data.aws_iam_policy_document.instance-assume-role-policy.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"] 
}
