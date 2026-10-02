module "network" {
  source      = "../../modules/network"
  name_prefix = var.name_prefix
}

module "rds" {
  source      = "../../modules/rds"
  name_prefix = var.name_prefix
}

module "rds_proxy" {
  source      = "../../modules/rds-proxy"
  name_prefix = var.name_prefix
}

module "ecs_service" {
  source      = "../../modules/ecs-service"
  name_prefix = var.name_prefix
}

module "lambda_processor" {
  source      = "../../modules/lambda-processor"
  name_prefix = var.name_prefix
}

module "amplify" {
  source      = "../../modules/amplify"
  name_prefix = var.name_prefix
}

module "observability" {
  source      = "../../modules/observability"
  name_prefix = var.name_prefix
}
