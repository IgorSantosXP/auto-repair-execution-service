# Mirrors app/lib/dynamo/schema.rb (single source of truth for the tables).
# One set of tables per environment, prefixed `auto-repair-<env>-execution`.
locals {
  tables = {
    "parts" = {
      hash_key   = "part_id"
      range_key  = null
      attributes = { part_id = "S" }
      ttl        = null
      indexes    = {}
    }
    "stock-movements" = {
      hash_key   = "part_id"
      range_key  = "movement_key"
      attributes = { part_id = "S", movement_key = "S" }
      ttl        = null
      indexes    = {}
    }
    "executions" = {
      hash_key   = "service_order_uuid"
      range_key  = null
      attributes = { service_order_uuid = "S", status = "S", queued_at = "S" }
      ttl        = null
      indexes = {
        "status-queued_at-index" = { hash_key = "status", range_key = "queued_at" }
      }
    }
    "outbox" = {
      hash_key   = "message_id"
      range_key  = null
      attributes = { message_id = "S" }
      ttl        = null
      indexes    = {}
    }
    "processed-messages" = {
      hash_key   = "message_id"
      range_key  = null
      attributes = { message_id = "S" }
      ttl        = "expires_at"
      indexes    = {}
    }
  }

  env_tables = merge([
    for env in keys(var.environments) : {
      for name, table in local.tables : "${env}/${name}" => merge(table, {
        env  = env
        name = "${var.project}-${env}-${var.service}-${name}"
      })
    }
  ]...)
}

resource "aws_dynamodb_table" "this" {
  for_each = local.env_tables

  name         = each.value.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = each.value.hash_key
  range_key    = each.value.range_key

  dynamic "attribute" {
    for_each = each.value.attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.indexes
    content {
      name            = global_secondary_index.key
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = "ALL"
    }
  }

  dynamic "ttl" {
    for_each = each.value.ttl == null ? [] : [each.value.ttl]
    content {
      attribute_name = ttl.value
      enabled        = true
    }
  }

  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Environment = each.value.env
  }
}
