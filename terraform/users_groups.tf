#Error: cannot create group member: invalidSyntax Members attribute cannot be 
# updated as group data-engineers can only be managed in account.

# NOTE:
# pci-readers and global-analysts are account-level groups. Free Edition has no
# account console or account API, so Terraform can't manage their membership.
# Add members by hand: Settings → Identity and access → Groups.


# Put Shaurave in the group
# resource "databricks_group_member" "shaurave_eng" {
#   group_id  = data.databricks_group.data_engineers.id
#   member_id = data.databricks_user.me.id
# }

# # Put Shaurave in the group
# resource "databricks_group_member" "shaurave_pci_reader" {
#   group_id  = data.databricks_group.pci_readers.id
#   member_id = data.databricks_user.me.id
# }

# # Put Shaurave in the group
# resource "databricks_group_member" "shaurave_global_analysts" {
#   group_id  = data.databricks_group.global_analysts.id
#   member_id = data.databricks_user.me.id
# }