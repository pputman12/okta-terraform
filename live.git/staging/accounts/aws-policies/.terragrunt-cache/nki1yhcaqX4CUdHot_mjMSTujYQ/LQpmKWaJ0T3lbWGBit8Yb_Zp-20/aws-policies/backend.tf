# Generated by Terragrunt. Sig: nIlQXj57tbuaRZEa
terraform {
  backend "s3" {
    bucket         = "terraform-okta-backend-pputman"
    dynamodb_table = "terraform-okta-backend-pputman"
    encrypt        = true
    key            = "staging/accounts/aws-policies/terraform.tfstate"
    region         = "us-east-2"
  }
}
