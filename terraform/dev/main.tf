module "app" {
  source = "../app"
  config = var.config
  secret_config = var.secret_config
  environment = "development"
}
resource "local_file" "kubeconfig" {
  content         = module.app.kubeconfig
  filename        = "${path.module}/generated/kubeconfig.yaml"
  file_permission = "0600"
}
resource "local_file" "talosconfig" {
  content         = module.app.talosconfig
  filename        = "${path.module}/generated/talosconfig.yaml"
  file_permission = "0600"
}
