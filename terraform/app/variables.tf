variable "environment" {
  type        = string
  description = "デプロイ環境 (production または development)"
  default     = "development"

  validation {
    condition     = contains(["production",  "development"], var.environment)
    error_message = "environment は 'production' または 'development' を指定してください。"
  }
}
