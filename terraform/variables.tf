variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region to deploy resources to"
  type        = string
  default     = "us-central1"
}

variable "prefix" {
  description = "A prefix for naming resources"
  type        = string
  default     = "cm-sandbox"
}

variable "target_repo" {
  description = "Git repository URL to automatically stage in the source bucket (set to 'none' or '' to disable)"
  type        = string
  default     = "https://github.com/thepawn1/cyber-homegym.git"
}

variable "enable_vpc_sc" {
  description = "Whether to create a VPC Service Controls perimeter around the project"
  type        = bool
  default     = false
}

variable "access_policy_id" {
  description = "The Access Context Manager Policy ID (numeric) required if enable_vpc_sc is true"
  type        = string
  default     = ""
}
