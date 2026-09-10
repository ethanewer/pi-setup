# escutcheon stack — service deploy directory

This directory describes the live deployment of the escutcheon services.

`live/` holds the configuration files currently in effect. These files were
created and edited by hand by the operations team before Terraform was adopted,
so Terraform has never managed them. They are real, on-disk truth: the running
services read them directly.
