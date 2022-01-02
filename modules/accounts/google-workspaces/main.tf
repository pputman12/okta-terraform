#------------------------------------------------------------------------------------------------------------------------------------- # VERSION REQUIREMENTS 
# Versions of Teraform and its providers pinned for stability
#-------------------------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = "~> 1.1.0"
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 3.20"
    }
    googleworkspace = {
      source  = "hashicorp/googleworkspace"
      version = "~> 0.6.0"
    }

  }
}

#-------------------------------------------------------------------------------------------------------------------------------------
# DATA GROUPS
# Data groups for okta users with google attribute set.  Group assignments commented out to switch from role based to attribute based
# access control
#-------------------------------------------------------------------------------------------------------------------------------------

#data "okta_groups" "okta_groups" {}


data "okta_users" "google_users" {
  for_each = toset([for name, account in var.accounts : name])
  search {
    name       = "profile.google"
    value      = each.value
    comparison = "eq"
  }
}

#-------------------------------------------------------------------------------------------------------------------------------------
# LOCAL VARIABLES FOR WORKSPACE USERS/PERMISSIONS 
# Configuring data structures to create users in google admin/workspace, and assign the proper roles 
#-------------------------------------------------------------------------------------------------------------------------------------

locals {
  #  app_groups     = [for group in data.okta_groups.okta_groups.groups : merge(group, { "role" = element(split("-", group.name ), 3), "account_name" = element(split("-", group.name), 2)}) if(var.app_name == element(split("-", group.name), 1)) ] 
  # app_group_assignments = [ for group  in local.app_groups :  group if contains(keys(var.accounts), group.account_name)]


  #-------------------------------------------------------------------------------------------------------------------------------------
  # APPLICATION CONFIGURATION 
  # Sets the domain to create for the application, its display name, and settings from specified variables 
  #-------------------------------------------------------------------------------------------------------------------------------------

  app_configuration = { for name, account in var.accounts : name => merge(account, { "app_display_name" = var.app_display_name, app_settings_json = var.app_settings_json }) }


  #-------------------------------------------------------------------------------------------------------------------------------------
  # GOOGLE WORKSPACE SEARCH
  # Builds a list of all users matching the google search, decoding the custom attributes (that we search on)  and merging them into the list 
  #-------------------------------------------------------------------------------------------------------------------------------------

  workspace_users = flatten([for search in data.okta_users.google_users : [for user in search.users : merge(user, jsondecode(user.custom_profile_attributes))]])


  #-------------------------------------------------------------------------------------------------------------------------------------
  # WORKSPACE ROLES
  # Build a list of all the roles needed to feed to the role ID datasource 
  #-------------------------------------------------------------------------------------------------------------------------------------

  workspace_roles = distinct(flatten([for user in local.workspace_users : [for role in user.gwsRoles : role]]))


  #-------------------------------------------------------------------------------------------------------------------------------------
  # MERGED USER PROFILES
  # This is merging in the old data structure with the new one with the user ids, after the user is created, so we can assign them
  # to the proper roles
  #-------------------------------------------------------------------------------------------------------------------------------------

  created_workspace_users = flatten([for user1name, user1 in local.workspace_users : [for user2name, user2 in googleworkspace_user.users : merge(user1, user2) if user1.email == user2.primary_email]])

  role_ids_to_user_ids = flatten([for user in local.created_workspace_users : [for role in user.gwsRoles : { "user_id" = user.id, "role_id" = data.googleworkspace_role.roles["${role}"].id, "role_name" = role, "email" = user.email }]])

  app_user_assignments = flatten([for username, user in local.workspace_users : distinct([for role in user.google : { "user" = user.login, "account_name" = role, "user_id" = user.id }])])
}

resource "googleworkspace_user" "users" {
  for_each      = { for user in local.workspace_users : user.email => user }
  primary_email = each.key
  password      = "34819d7beeabb9260a5c854bc85b3e44"
  hash_function = "MD5"

  name {
    family_name = each.value.last_name
    given_name  = each.value.first_name
  }
}

data "googleworkspace_role" "roles" {
  for_each = toset(local.workspace_roles)
  name     = each.value
}

resource "googleworkspace_role_assignment" "role_assignment" {
  for_each    = { for user in local.role_ids_to_user_ids : "${user.role_name}-${user.email}" => user }
  assigned_to = each.value.user_id
  role_id     = each.value.role_id
}

module "saml-app" {
  source            = "../../../modules/accounts/saml-app/"
  accounts          = var.accounts
  okta_appname      = var.okta_appname
  app_configuration = local.app_configuration
  user_assignments  = local.app_user_assignments
  #  group_assignments = local.app_group_assignments 
}
