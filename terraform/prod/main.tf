module "app" {
  source = "../app"
  config = var.config
  secret_config = var.secret_config
  environment = "production"
}