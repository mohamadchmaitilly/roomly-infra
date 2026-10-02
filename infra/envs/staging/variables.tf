variable "name_prefix" {
  description = "Prefix applied to all named AWS resources. Shared across every module so names stay unique within the account."
  type        = string
  default     = "roomly"
}
