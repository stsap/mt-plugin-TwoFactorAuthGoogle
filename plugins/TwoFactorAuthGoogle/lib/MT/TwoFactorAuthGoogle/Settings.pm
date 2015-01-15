package MT::TwoFactorAuthGoogle::Settings;
use strict;
use base qw|MT::Object|;

__PACKAGE__->install_properties({
	column_defs => {
		"id" => "integer not null auto_increment",
		"author_id" => "integer not null",
		"enable_twofactorauth" => "boolean",
		"secret" => "text not null",
	},
	indexes => {
		"author_id" => 1,
		"created_on" => 1,
		"modified_on" => 1
	},
	child_of => "MT::Author",
	audit => 1,
	datasource => "twofactorauthgoogle",
	primary_key => "id",
});

1;
