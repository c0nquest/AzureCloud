locals {
  name_prefix = var.prefix
  # name_prefix         = "${var.name_prefix != "" ? var.name_prefix : local.default_name_prefix}"
  location            = var.location
  resource_group_name = "${var.prefix}-${var.resource_group_name}"
  rg_name             = element(azurerm_resource_group.network.*.name, 0)
  rg_location         = element(azurerm_resource_group.network.*.location, 0)
}

resource "azurerm_resource_group" "network" {
  count    = var.create_resource_group == true ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = merge({ "ResourceName" = format("%s", var.resource_group_name) }, var.tags, )
}

resource "azurerm_virtual_network" "vnet" {
  name                = lower("vnet-spoke-${var.spoke_vnet_name}-${local.location}")
  location            = local.rg_location
  resource_group_name = local.rg_name
  address_space       = var.vnet_address_space
  dns_servers         = var.dns_servers
  tags                = merge({ "ResourceName" = lower("vnet-spoke-${var.spoke_vnet_name}-${local.location}") }, var.tags, )
}

resource "azurerm_subnet" "snet" {
  for_each             = var.subnets
  name                 = lower(format("snet-%s-${var.spoke_vnet_name}-${local.location}", each.value.subnet_name))
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.subnet_address_prefix
  service_endpoints    = lookup(each.value, "service_endpoints", [])
}

resource "azurerm_network_security_group" "nsg" {
  for_each            = var.subnets
  name                = lower("nsg_${each.key}_in")
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = merge({ "ResourceName" = lower("nsg_${each.key}_in") }, var.tags, )
  dynamic "security_rule" {
    for_each = concat(lookup(each.value, "nsg_inbound_rules", []), lookup(each.value, "nsg_outbound_rules", []))
    content {
      name                       = security_rule.value[0] == "" ? "Default_Rule" : security_rule.value[0]
      priority                   = security_rule.value[1]
      direction                  = security_rule.value[2] == "" ? "Inbound" : security_rule.value[2]
      access                     = security_rule.value[3] == "" ? "Allow" : security_rule.value[3]
      protocol                   = security_rule.value[4] == "" ? "Tcp" : security_rule.value[4]
      source_port_range          = "*"
      destination_port_range     = security_rule.value[5] == "" ? "*" : security_rule.value[5]
      source_address_prefix      = security_rule.value[6] == "" ? element(each.value.subnet_address_prefix, 0) : security_rule.value[6]
      destination_address_prefix = security_rule.value[7] == "" ? element(each.value.subnet_address_prefix, 0) : security_rule.value[7]
      description                = "${security_rule.value[2]}_Port_${security_rule.value[5]}"
    }
  }
}


resource "azurerm_subnet_network_security_group_association" "nsg-assoc" {
  for_each                  = var.subnets
  subnet_id                 = azurerm_subnet.snet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}


