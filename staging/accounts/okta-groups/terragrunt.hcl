include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "github.com/my-gh-account/infrastructure-modules//accounts/okta-groups"
}

inputs = {
  apps = {
    #AWS Rules format:  aws-accountnumber-awsPolicyName
    "aws-975678609170-AdministratorAccess" = { rule = join(" ", [ # This join gives us a better way to specify larger, more complex rules on multiple lines.
      "user.email == \"putman.patrick@gmail.com\"       OR",            # Admin
      "user.email == \"test@deserthomescleaning.com\"   OR",
      "user.email == \"test2@deserthomescleaning.com\""
      ])
    },
    "aws-975678609170-test_policy3" = { rule = "user.email == \"test@deserthomescleaning.com\"" },
    "aws-975678609170-AmazonS3FullAccess" = { rule = join(" ", [  # This join gives us a better way to specify larger, more complex rules on multiple lines.
      "user.email == \"putman.patrick@gmail.com\"  OR",               # Admin
      "user.email == \"test@deserthomescleaning.com\""
      ])
    },
    #Slack Rules Formation:  slack-workspace
    "slack-deserthomescleaning" = { rule = join(" ", [
      "user.email == \"patrick@deserthomescleaning.com\" OR",
      "user.email == \"test@deserthomescleaning.com\""
      ])
    },
    "slack-security_team" = { rule = join(" ", [
      "user.email == \"putman.patrick@gmail.com\" OR",
      "user.email == \"patrick@teramind.co\""
      ])
    }
  }
}
